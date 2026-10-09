#!/usr/bin/env bash
# Partie 4 : image Docker, tests, epinglage, publication dans l'ACR de la seance 1.
# Docker Desktop doit etre ouvert. Usage : bash lancer_partie_4.sh
cd "$(dirname "$0")"
source .venv/bin/activate
mkdir -p captures
C=captures

echo "== Q3.1 : chargement a chaud (modules deja importes)"
python3 -c "
import sklearn, pandas, numpy, time, joblib
t = time.perf_counter(); joblib.load('model/modele.joblib')
print(f'1er chargement (imports des sous-modules compris) : {(time.perf_counter() - t) * 1000:.1f} ms')
t = time.perf_counter(); joblib.load('model/modele.joblib')
print(f'2e chargement, processus deja chaud : {(time.perf_counter() - t) * 1000:.1f} ms')" | tee $C/chargement_chaud.txt

echo "== Mesure 13 : construction a froid (requirements non epingle)"
printf "flask\ngunicorn\nscikit-learn\npandas\njoblib\n" > requirements.txt
docker rm -f dermascan-api >/dev/null 2>&1
docker rmi dermascan-api:1.0.0 >/dev/null 2>&1
debut=$(date +%s)
docker build --no-cache -t dermascan-api:1.0.0 . > $C/build.log 2>&1 || { tail -20 $C/build.log; exit 1; }
echo "duree de construction : $(( $(date +%s) - debut )) s" | tee $C/mesure13.txt
docker images dermascan-api:1.0.0 --format "taille : {{.Size}}" | tee -a $C/mesure13.txt
echo "couches : $(docker history -q dermascan-api:1.0.0 | wc -l | tr -d ' ')" | tee -a $C/mesure13.txt
echo "paquets pip freeze : $(docker run --rm dermascan-api:1.0.0 pip freeze | wc -l | tr -d ' ')" | tee -a $C/mesure13.txt

echo "== Mesure 15 : versions dans l'image vs dans le paquet"
docker run --rm dermascan-api:1.0.0 pip show scikit-learn numpy pandas joblib | grep -E "^(Name|Version)" | tee $C/versions_image.txt
echo "paquet : $(python3 -c "import joblib; print(joblib.load('model/modele.joblib')['versions'])")" | tee -a $C/versions_image.txt

echo "== Test du conteneur non epingle"
docker run -d --name dermascan-api -p 8000:8000 dermascan-api:1.0.0 >/dev/null
for _ in $(seq 60); do curl -s -o /dev/null localhost:8000/health && break; sleep 1; done
{ curl -s -i localhost:8000/health; echo
  curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge.json; echo
  echo "--- docker logs"; docker logs dermascan-api 2>&1 | tail -40; } | tee $C/conteneur_non_epingle.txt
docker rm -f dermascan-api >/dev/null

echo "== Epinglage des versions de l'entrainement"
pip freeze | grep -iE '^(flask|gunicorn|scikit-learn|pandas|joblib|numpy|scipy)==' > requirements.txt
cat requirements.txt | tee $C/requirements_epingle.txt
docker build -t dermascan-api:1.0.0 . > $C/build_epingle.log 2>&1 || { tail -20 $C/build_epingle.log; exit 1; }
docker run -d --name dermascan-api -p 8000:8000 dermascan-api:1.0.0 >/dev/null
for _ in $(seq 60); do curl -s -o /dev/null localhost:8000/health && break; sleep 1; done
{ curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge.json; echo; } | tee $C/conteneur_epingle.txt
docker rm -f dermascan-api >/dev/null

echo "== Mesure 16 : publication dans l'ACR"
if command -v az >/dev/null; then AZ=1; else AZ=0; fi
[ -n "$ACR_NAME" ] || { [ $AZ = 1 ] && ACR_NAME=$(az acr list --query "[0].name" -o tsv); }
[ -n "$ACR_NAME" ] || { echo "Aucun registre : definis ACR_NAME=<nom> ou installe Azure CLI."; exit 1; }
IMAGE_FULL="$ACR_NAME.azurecr.io/dermascan-api:1.0.0"
echo "registre : $ACR_NAME" | tee $C/mesure16.txt
if [ $AZ = 1 ]; then az acr login --name "$ACR_NAME" || exit 1; fi
docker build --platform linux/amd64 --provenance=false -t "$IMAGE_FULL" . > $C/build_amd64.log 2>&1 || { tail -20 $C/build_amd64.log; exit 1; }
debut=$(date +%s)
docker push "$IMAGE_FULL" 2>&1 | tee -a $C/mesure16.txt
echo "duree du push : $(( $(date +%s) - debut )) s" | tee -a $C/mesure16.txt
if [ $AZ = 1 ]; then
  az acr repository show-tags --name "$ACR_NAME" --repository dermascan-api -o table | tee -a $C/mesure16.txt
  az acr repository list --name "$ACR_NAME" -o table | tee -a $C/mesure16.txt
else
  echo "(tags a verifier dans le portail Azure : registre > Referentiels > dermascan-api)" | tee -a $C/mesure16.txt
fi
echo; echo "Termine. Resultats dans captures/."

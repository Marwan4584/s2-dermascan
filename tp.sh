#!/usr/bin/env bash
# TP2 DermaScan — toutes les etapes dans un seul script.
#
#   bash tp.sh modele 0.90   parties 1 et 2 : donnees, exploration, entrainement (0.90 = rappel vise)
#   bash tp.sh api           partie 3       : tests de l'API, latence, /health sans modele
#   bash tp.sh registre      cree le groupe et le registre ACR (une seule fois)
#   bash tp.sh docker        partie 4       : image, versions, epinglage, publication
#   bash tp.sh nettoyage     fin de seance  : docker prune et controles Azure
#
# Chaque etape ecrit ses resultats dans captures/.
cd "$(dirname "$0")"
mkdir -p captures data model
C=captures
SUFFIXE=korich
RG="rg-dermascan-registre-$SUFFIXE"
ACR_NAME="${ACR_NAME:-acrdermascan$SUFFIXE}"
A_DETRUIRE=2026-12-31
export PATH="$HOME/.azcli/bin:$PATH"   # Azure CLI installe avec pip (Homebrew inutilisable ici)

venv() {
  [ -d .venv ] || python3 -m venv .venv
  source .venv/bin/activate
}

attendre() {  # attend qu'une API reponde sur le port $1 (60 s max)
  for _ in $(seq 60); do curl -s -o /dev/null "localhost:$1/health" && return 0; sleep 1; done
  echo "ECHEC : rien ne repond sur le port $1"; return 1
}

predire() {  # POST /predict sur le port $1 avec le fichier $2
  curl -s -i -X POST "localhost:$1/predict" -H "Content-Type: application/json" ${2:+-d @$2}; echo
}

# ---------------------------------------------------------------- parties 1 et 2
modele() {
  local rappel="${1:?Indique le rappel vise, ex. : bash tp.sh modele 0.90}"
  set -e
  venv
  pip install -q --upgrade pip
  pip install -q pandas scikit-learn joblib flask gunicorn requests kaggle
  if [ ! -f data/train-metadata.csv ]; then
    kaggle competitions download -c isic-2024-challenge -f train-metadata.csv -p data/
    unzip -o data/train-metadata.csv.zip -d data/ && rm -f data/train-metadata.csv.zip
  fi
  { ls -lh data/train-metadata.csv
    python3 explorer.py
    python3 entrainer.py --rappel "$rappel"
  } | tee $C/parties_1_2.txt
}

# ---------------------------------------------------------------- partie 3
api() {
  venv
  {
  echo "== Q3.1 : chargement du modele"
  python3 -c "
import time, joblib
t = time.perf_counter(); joblib.load('model/modele.joblib')
print(f'1er chargement (imports compris) : {(time.perf_counter() - t) * 1000:.1f} ms')
t = time.perf_counter(); joblib.load('model/modele.joblib')
print(f'2e chargement, processus chaud   : {(time.perf_counter() - t) * 1000:.1f} ms')"

  PORT=8000 python3 app.py > /dev/null 2>&1 & local pid=$!
  attendre 8000
  echo "== GET /health";              curl -s -i localhost:8000/health; echo
  echo "== GET /model/info";          curl -s -i localhost:8000/model/info | head -c 700; echo
  echo "== POST /predict valide";     predire 8000 charge.json
  echo "== POST /predict incomplete"; predire 8000 charge_incomplete.json
  echo "== POST /predict vide";       predire 8000
  echo "== Mesure 12 : latence de 10 appels"
  python3 -c "
import json, statistics, time, requests
charge = json.load(open('charge.json')); d = []
for _ in range(10):
    t = time.perf_counter()
    requests.post('http://localhost:8000/predict', json=charge, timeout=10).raise_for_status()
    d.append((time.perf_counter() - t) * 1000)
print(f'min {min(d):.1f} ms | mediane {statistics.median(d):.1f} ms | max {max(d):.1f} ms')"
  kill $pid; sleep 1

  echo "== Q3.3 : API sans modele"
  MODEL_PATH=absent.joblib PORT=8001 python3 app.py > /dev/null 2>&1 & pid=$!
  attendre 8001
  curl -s -i localhost:8001/health; echo
  kill $pid
  } 2>&1 | tee $C/partie_3_api.txt
}

# ---------------------------------------------------------------- registre ACR
registre() {
  az account show >/dev/null 2>&1 || az login >/dev/null
  az group show --name "$RG" -o none 2>/dev/null || az group create --name "$RG" \
     --location francecentral --tags a_detruire=$A_DETRUIRE projet=dermascan -o table
  # L'abonnement etudiant n'autorise que certaines regions : on les lit dans la policy.
  local regions
  regions=$(az policy assignment list --query "[].parameters.listOfAllowedLocations.value[]" -o tsv | sort -u)
  echo "Regions autorisees : $regions"
  for r in $regions; do
    az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic --location "$r" \
       --tags a_detruire=$A_DETRUIRE -o table && break
  done
  az acr show --name "$ACR_NAME" --query "{nom:name, serveur:loginServer, region:location}" -o table
}

# ---------------------------------------------------------------- partie 4
docker_partie() {
  venv
  docker info >/dev/null 2>&1 || { open -a Docker; for _ in $(seq 90); do docker info >/dev/null 2>&1 && break; sleep 2; done; }
  {
  echo "== Mesure 13 : construction a froid, requirements non epingle"
  printf "flask\ngunicorn\nscikit-learn\npandas\njoblib\n" > requirements.txt
  docker rm -f dermascan-api >/dev/null 2>&1; docker rmi dermascan-api:1.0.0 >/dev/null 2>&1
  local debut=$(date +%s)
  docker build -q --no-cache -t dermascan-api:1.0.0 . >/dev/null || return 1
  echo "duree de construction : $(( $(date +%s) - debut )) s"
  docker images dermascan-api:1.0.0 --format "taille : {{.Size}}"
  echo "couches : $(docker history -q dermascan-api:1.0.0 | wc -l | tr -d ' ')"
  echo "paquets pip freeze : $(docker run --rm dermascan-api:1.0.0 pip freeze | wc -l | tr -d ' ')"

  echo "== Mesure 15 : versions de l'image et du paquet"
  docker run --rm dermascan-api:1.0.0 pip show scikit-learn numpy pandas joblib | grep -E "^(Name|Version)"
  echo "paquet : $(python3 -c "import joblib; print(joblib.load('model/modele.joblib')['versions'])")"

  echo "== Conteneur, requirements non epingle"
  docker run -d --name dermascan-api -p 8000:8000 dermascan-api:1.0.0 >/dev/null
  attendre 8000 && { curl -s localhost:8000/health; echo; predire 8000 charge.json; }
  docker logs dermascan-api 2>&1 | tail -10
  docker rm -f dermascan-api >/dev/null

  echo "== Epinglage des versions de l'entrainement"
  pip freeze | grep -iE '^(flask|gunicorn|scikit-learn|pandas|joblib|numpy|scipy)==' > requirements.txt
  cat requirements.txt
  docker build -q -t dermascan-api:1.0.0 . >/dev/null || return 1
  docker run -d --name dermascan-api -p 8000:8000 dermascan-api:1.0.0 >/dev/null
  attendre 8000 && predire 8000 charge.json
  docker rm -f dermascan-api >/dev/null

  echo "== Mesure 16 : publication"
  local image="$ACR_NAME.azurecr.io/dermascan-api:1.0.0"
  az acr login --name "$ACR_NAME" || return 1
  docker build -q --platform linux/amd64 --provenance=false -t "$image" . >/dev/null || return 1
  debut=$(date +%s)
  docker push "$image" | tail -3
  echo "duree du push : $(( $(date +%s) - debut )) s"
  az acr repository show-tags --name "$ACR_NAME" --repository dermascan-api -o table
  } 2>&1 | tee $C/partie_4_docker.txt
}

# ---------------------------------------------------------------- nettoyage
nettoyage() {
  {
  echo "== Docker"
  docker rm -f dermascan-api 2>/dev/null
  docker system prune -f | tail -1
  echo "== Ressources actives dans $RG"
  az resource list --resource-group "$RG" -o table
  echo "== Etiquettes du groupe"
  az group show --name "$RG" --query tags -o json
  echo "== Groupes de l'abonnement (un seul attendu)"
  az group list -o table
  echo "== Tags publies"
  az acr repository show-tags --name "$ACR_NAME" --repository dermascan-api -o table
  } 2>&1 | tee $C/nettoyage.txt
  echo "A relever a la main : credit restant sur https://www.microsoftazuresponsorships.com/Balance"
}

case "$1" in
  modele)    modele "$2" ;;
  api)       api ;;
  registre)  registre ;;
  docker)    docker_partie ;;
  nettoyage) nettoyage ;;
  *) sed -n 2,9p "$0"; exit 1 ;;
esac

# TP2 DermaScan — marche à suivre

Toutes les commandes se lancent depuis `s2-dermascan/`. Chaque script affiche
les mesures numérotées de l'énoncé : recopie-les dans `EXPLORATION.md` et `MESURES.md`.

## 0. Avant tout
- Remplis le **tableau de décisions** en tête de `MESURES.md`, dont le **rappel visé**
  (par exemple 0.90 ou 0.95) — **avant** de lancer quoi que ce soit (question 0.1).
- Rappelle les variables de la séance 1 :
  ```bash
  export ACR_NAME=<ton_registre>        # ex. acrdermascanxxx
  export RG=rg-dermascan-registre-<suffixe>
  export IMAGE_FULL="$ACR_NAME.azurecr.io/dermascan-api:1.0.0"
  az acr show --name "$ACR_NAME" --query loginServer -o tsv   # doit répondre
  ```

## 1. Environnement et données (Partie 1)
```bash
python3 -m venv .venv && source .venv/bin/activate      # Windows : .venv\Scripts\activate
pip install --upgrade pip
pip install pandas scikit-learn joblib flask gunicorn requests kaggle
# Kaggle : accepter les Rules de isic-2024-challenge sur le site, puis
kaggle auth login
kaggle competitions download -c isic-2024-challenge -f train-metadata.csv -p data/
unzip -o data/train-metadata.csv.zip -d data/ && rm data/train-metadata.csv.zip
ls -lh data/train-metadata.csv
```
Puis :
```bash
python3 explorer.py | tee captures/exploration.txt     # mesures 1 à 5
```

## 2. Entraînement (Partie 2)
```bash
python3 entrainer.py --rappel 0.90 | tee captures/entrainement.txt   # mets TON rappel
```
Affiche les mesures 6 à 10, écrit `model/modele.joblib`, `charge.json` (une vraie
ligne du test) et `charge_incomplete.json`.
Pour la question 2.1 (stabilité), relance avec `--graine 1`, `--graine 7`… et compare.

## 3. API (Partie 3)
```bash
PORT=8000 python3 app.py &
curl -s -i http://localhost:8000/health | head -1
curl -s http://localhost:8000/health
curl -s http://localhost:8000/model/info
curl -s -i -X POST http://localhost:8000/predict -H "Content-Type: application/json" -d @charge.json
curl -s -i -X POST http://localhost:8000/predict -H "Content-Type: application/json" -d @charge_incomplete.json
curl -s -i -X POST http://localhost:8000/predict -H "Content-Type: application/json"
python3 latence.py                                     # mesure 12
```
Question 3.3 : `mv model/modele.joblib /tmp/`, relance l'API → `/health` renvoie **503**.
Remets le fichier en place ensuite.
Arrête l'API : `kill %1` (ou `pkill -f app.py`).

## 4. Docker et publication (Partie 4)
Dans le `Dockerfile`, mets `PYTHON_VERSION` égal à **ta** version de la mesure 1 (ex. 3.12).
```bash
docker build -t dermascan-api:1.0.0 .
docker images dermascan-api                            # taille (mesure 13)
docker history dermascan-api:1.0.0 | wc -l             # couches
docker run --rm dermascan-api:1.0.0 pip freeze | wc -l # paquets
docker run -d --name dermascan-api -p 8000:8000 dermascan-api:1.0.0
curl -s -X POST http://localhost:8000/predict -H "Content-Type: application/json" -d @charge.json
docker logs dermascan-api                              # mesure 15 : erreur éventuelle
```
**Mesure 15 / épinglage** : le `requirements.txt` fourni n'est volontairement pas épinglé.
Relève la version de scikit-learn installée dans l'image
(`docker run --rm dermascan-api:1.0.0 pip show scikit-learn`), compare-la au champ
`versions` de `/model/info`, puis épingle **tes** versions de la mesure 1 :
```bash
pip freeze | grep -iE '^(flask|gunicorn|scikit-learn|pandas|joblib|numpy|scipy)==' > requirements.txt
docker rm -f dermascan-api
docker build -t dermascan-api:1.0.0 .
```
Publication :
```bash
az acr login --name "$ACR_NAME"
docker build --platform linux/amd64 --provenance=false -t "$IMAGE_FULL" .
time docker push "$IMAGE_FULL"                        # durée + digest (mesure 16)
az acr repository show-tags --name "$ACR_NAME" --repository dermascan-api --output table
```

## 5. Model card + nettoyage
- Remplis `MODEL_CARD.md`.
- Nettoyage :
  ```bash
  docker rm -f dermascan-api 2>/dev/null
  docker system prune -f
  deactivate
  az resource list --resource-group "$RG" --output table
  az group show --name "$RG" --query "tags" --output json
  az group list --output table          # un seul groupe : celui du registre
  ```
- Quitte Docker Desktop et éteins ta machine.

## À ne pas déposer
`data/train-metadata.csv` (246 Mo) et `model/modele.joblib` (se régénère).

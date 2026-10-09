#!/usr/bin/env bash
# Usage : bash lancer_parties_1_a_3.sh 0.90     (0.90 = TON rappel vise)
set -euo pipefail
cd "$(dirname "$0")"
RAPPEL="${1:?Indique ton rappel vise, ex. : bash lancer_parties_1_a_3.sh 0.90}"
mkdir -p data model captures

[ -d .venv ] || python3 -m venv .venv
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q pandas scikit-learn joblib flask gunicorn requests kaggle

if [ ! -f data/train-metadata.csv ]; then
  kaggle competitions download -c isic-2024-challenge -f train-metadata.csv -p data/
  unzip -o data/train-metadata.csv.zip -d data/ && rm -f data/train-metadata.csv.zip
fi
ls -lh data/train-metadata.csv | tee captures/poids_fichier.txt

python3 explorer.py | tee captures/exploration.txt
python3 entrainer.py --rappel "$RAPPEL" | tee captures/entrainement.txt

PORT=8000 python3 app.py > captures/api.log 2>&1 &
API=$!; trap 'kill $API 2>/dev/null' EXIT; sleep 3
{
  echo "== GET /health";            curl -s -i localhost:8000/health; echo
  echo "== GET /model/info";        curl -s -i localhost:8000/model/info | head -c 600; echo
  echo "== POST /predict valide";   curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge.json; echo
  echo "== POST /predict incomplete"; curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge_incomplete.json; echo
  echo "== POST /predict vide";     curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json"; echo
  echo "== Latence";                python3 latence.py
} | tee captures/api.txt
kill $API; sleep 1

echo "== Question 3.3 : API sans modele"
MODEL_PATH=absent.joblib PORT=8001 python3 app.py > /dev/null 2>&1 &
API=$!; sleep 3
curl -s -i localhost:8001/health | tee captures/health_sans_modele.txt; echo
echo; echo "Termine. Resultats dans le dossier captures/."

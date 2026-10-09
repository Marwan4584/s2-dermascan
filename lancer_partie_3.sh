#!/usr/bin/env bash
# Partie 3 seule (le modele doit deja exister) : bash lancer_partie_3.sh
cd "$(dirname "$0")"
source .venv/bin/activate
mkdir -p captures

attendre() {  # attend que l'API reponde sur le port $1 (max 60 s)
  for _ in $(seq 60); do curl -s -o /dev/null "localhost:$1/health" && return 0; sleep 1; done
  echo "L'API ne demarre pas, voir captures/api.log"; exit 1
}

echo "== Question 3.1 : temps de chargement du modele"
python3 -c "
import time, joblib
t = time.perf_counter(); joblib.load('model/modele.joblib')
print(f'chargement joblib.load : {(time.perf_counter() - t) * 1000:.0f} ms')" | tee captures/chargement.txt

PORT=8000 python3 app.py > captures/api.log 2>&1 &
API=$!; trap 'kill $API 2>/dev/null' EXIT
attendre 8000
{
  echo "== GET /health";              curl -s -i localhost:8000/health; echo
  echo "== GET /model/info";          curl -s -i localhost:8000/model/info | head -c 700; echo
  echo "== POST /predict valide";     curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge.json; echo
  echo "== POST /predict incomplete"; curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json" -d @charge_incomplete.json; echo
  echo "== POST /predict vide";       curl -s -i -X POST localhost:8000/predict -H "Content-Type: application/json"; echo
  echo "== Latence (mesure 12)";      python3 latence.py
} | tee captures/api.txt
kill $API; sleep 1

echo "== Question 3.3 : API sans modele"
MODEL_PATH=absent.joblib PORT=8001 python3 app.py > /dev/null 2>&1 &
API=$!
attendre 8001
curl -s -i localhost:8001/health | tee captures/health_sans_modele.txt; echo
echo; echo "Termine. Resultats dans captures/."

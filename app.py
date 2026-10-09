"""Partie 3 — API d'inference DermaScan.

    PORT=8000 python3 app.py              # developpement
    gunicorn -b 0.0.0.0:8000 app:app      # comme dans l'image

Variables lues : PORT (defaut 8000), MODEL_PATH (defaut model/modele.joblib),
SEUIL (defaut : celui du paquet).
"""
import os

import joblib
import numpy as np
import pandas as pd
from flask import Flask, jsonify, request

# Chargement au demarrage, PAS dans la fonction de vue.
# Un modele absent n'empeche pas le processus de demarrer : /health le signale.
PAQUET, PIPELINE, ERREUR = None, None, None
try:
    PAQUET = joblib.load(os.environ.get("MODEL_PATH", "model/modele.joblib"))
    PIPELINE = PAQUET["pipeline"]
    SEUIL = float(os.environ.get("SEUIL", PAQUET["seuil"]))
    COLONNES = PAQUET["colonnes_attendues"]
    NUMERIQUES = set(PAQUET.get("colonnes_numeriques", []))
except Exception as exc:  # noqa: BLE001 — on veut tout capturer ici
    PIPELINE = None
    ERREUR = f"{type(exc).__name__}: {exc}"

app = Flask(__name__)


@app.get("/health")
def health():
    if PIPELINE is None:
        return jsonify({"status": "indisponible", "model_loaded": False, "erreur": ERREUR}), 503
    return jsonify({"status": "ok", "model_loaded": True, "version_modele": PAQUET["version"]}), 200


@app.get("/model/info")
def model_info():
    if PIPELINE is None:
        return jsonify({"error": "modele non charge", "erreur": ERREUR}), 503
    return jsonify({
        "version": PAQUET["version"],
        "seuil": SEUIL,
        "seuil_paquet": PAQUET["seuil"],
        "rappel_cible": PAQUET["rappel_cible"],
        "metriques": PAQUET["metriques"],
        "prevalence_entrainement": PAQUET["prevalence_entrainement"],
        "nb_colonnes_attendues": len(COLONNES),
        "colonnes_attendues": COLONNES,
        "versions": PAQUET.get("versions"),
        "entraine_le": PAQUET.get("entraine_le"),
    })


@app.post("/predict")
def predict():
    if PIPELINE is None:
        return jsonify({"error": "modele non charge"}), 503

    charge = request.get_json(silent=True)
    if not isinstance(charge, dict) or not charge:
        return jsonify({"error": "corps JSON absent ou invalide : objet attendu"}), 400

    # Valider AVANT de predire : 400 qui nomme ce qui manque, jamais 500.
    manquantes = [c for c in COLONNES if c not in charge]
    if manquantes:
        return jsonify({"error": "variables manquantes",
                        "nb_manquantes": len(manquantes),
                        "manquantes": manquantes[:10]}), 400

    ligne = {}
    for c in COLONNES:
        v = charge[c]
        if c in NUMERIQUES:
            try:
                ligne[c] = np.nan if v is None else float(v)
            except (TypeError, ValueError):
                return jsonify({"error": f"valeur non numerique pour {c}", "valeur": v}), 400
        else:
            ligne[c] = np.nan if v is None else str(v)
    X = pd.DataFrame([ligne], columns=COLONNES)

    proba = float(PIPELINE.predict_proba(X)[0, 1])
    return jsonify({
        "probabilite_maligne": round(proba, 6),
        "seuil": SEUIL,
        "decision": "examen_dermatologue" if proba >= SEUIL else "pas_d_alerte",
        "version_modele": PAQUET["version"],
        "rappel_cible": PAQUET["rappel_cible"],
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))

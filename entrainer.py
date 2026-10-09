"""Partie 2 — Decoupage par patient, pipeline, evaluation, seuil, serialisation.

Le rappel vise se decide AVANT de lancer le script (tableau de decisions) :

    python3 entrainer.py --rappel 0.90

Affiche les mesures 6 a 10, ecrit model/modele.joblib,
charge.json (une ligne reelle du test) et charge_incomplete.json.
"""
import argparse
import json
import os
import platform
import time
from datetime import datetime, timezone

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, average_precision_score,
                             precision_recall_curve, roc_auc_score)
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

parser = argparse.ArgumentParser()
parser.add_argument("--rappel", type=float, required=True,
                    help="rappel vise, decide avant toute mesure (ex. 0.90)")
parser.add_argument("--graine", type=int, default=42)
parser.add_argument("--test", type=float, default=0.2, help="part des patients en test")
args = parser.parse_args()

VERSION = "1.0.0"
FUITES = ["iddx_full", "iddx_1", "iddx_2", "iddx_3", "iddx_4", "iddx_5",
          "mel_thick_mm", "mel_mitotic_index", "lesion_id"]
IDENTIFIANTS = ["isic_id", "patient_id"]
# Metadonnees de provenance, pas des mesures de la lesion.
ADMINISTRATIVES = ["attribution", "copyright_license"]

d = pd.read_csv("data/train-metadata.csv", low_memory=False)
y = d["target"].to_numpy()
groupes = d["patient_id"].to_numpy()

constantes = [c for c in d.columns if c not in FUITES and d[c].nunique(dropna=True) <= 1]
a_retirer = set(FUITES + IDENTIFIANTS + ADMINISTRATIVES + constantes + ["target"])
X = d[[c for c in d.columns if c not in a_retirer]]

colonnes_numeriques = X.select_dtypes(include="number").columns.tolist()
colonnes_categorielles = [c for c in X.columns if c not in colonnes_numeriques]
colonnes_attendues = X.columns.tolist()
print(f"Variables utilisees : {len(colonnes_attendues)} "
      f"({len(colonnes_numeriques)} numeriques, {len(colonnes_categorielles)} categorielles)")
print("Categorielles :", colonnes_categorielles)
print("Constantes retirees :", constantes)

# ---------------------------------------------------------------- 2.1
decoupe = GroupShuffleSplit(n_splits=1, test_size=args.test, random_state=args.graine)
train, test = next(decoupe.split(X, y, groups=groupes))
assert not (set(groupes[train]) & set(groupes[test])), "fuite de patients"

print("\nMESURE 6 — decoupage (graine", args.graine, ")")
print(f"{'':<12}{'Entrainement':>14}{'Test':>12}")
for libelle, f in (("lignes", lambda i: f"{len(i)}"),
                   ("patients", lambda i: f"{len(set(groupes[i]))}"),
                   ("positifs", lambda i: f"{int(y[i].sum())}"),
                   ("taux", lambda i: f"{y[i].mean():.4%}")):
    print(f"{libelle:<12}{f(train):>14}{f(test):>12}")
print("Intersection des patients train/test : 0 (assert OK)")

X_train, X_test = X.iloc[train], X.iloc[test]
y_train, y_test = y[train], y[test]

# ---------------------------------------------------------------- 2.2
pre = ColumnTransformer([
    ("num", Pipeline([("imputation", SimpleImputer(strategy="median")),
                      ("echelle", StandardScaler())]), colonnes_numeriques),
    ("cat", Pipeline([("imputation", SimpleImputer(strategy="most_frequent")),
                      ("encodage", OneHotEncoder(handle_unknown="ignore"))]),
     colonnes_categorielles),
])

# ---------------------------------------------------------------- 2.3
modele = Pipeline([("pre", pre),
                   ("clf", LogisticRegression(max_iter=1000, class_weight="balanced"))])

reference = DummyClassifier(strategy="most_frequent").fit(X_train, y_train)

t0 = time.perf_counter()
modele.fit(X_train, y_train)
duree_entrainement = time.perf_counter() - t0

proba = modele.predict_proba(X_test)[:, 1]
proba_ref = reference.predict_proba(X_test)[:, 1]

def ligne(nom, pred, p):
    acc = accuracy_score(y_test, pred)
    roc = roc_auc_score(y_test, p)
    pr = average_precision_score(y_test, p)
    print(f"{nom:<24}{acc:>12.4%}{roc:>10.4f}{pr:>10.4f}")
    return {"exactitude": acc, "roc_auc": roc, "pr_auc": pr}

print("\nMESURE 7 — ensemble de test")
print(f"{'Modele':<24}{'Exactitude':>12}{'ROC-AUC':>10}{'PR-AUC':>10}")
m_ref = ligne("DummyClassifier", reference.predict(X_test), proba_ref)
m_lr = ligne("Regression logistique", modele.predict(X_test), proba)
hasard = y_test.mean()
print(f"{'Hasard (PR-AUC)':<24}{'—':>12}{'—':>10}{hasard:>10.4f}")

# ---------------------------------------------------------------- 2.4
def confusion(seuil):
    alerte = proba >= seuil
    vp = int((alerte & (y_test == 1)).sum())
    fp = int((alerte & (y_test == 0)).sum())
    fn = int((~alerte & (y_test == 1)).sum())
    rap = vp / (vp + fn) if vp + fn else 0.0
    prec = vp / (vp + fp) if vp + fp else 0.0
    return rap, prec, vp, fp, fn, 1000 * alerte.mean()

print("\nMESURE 8 — compromis rappel / precision")
print(f"{'Seuil':<7}{'Rappel':>8}{'Precision':>11}{'VP':>6}{'FP':>8}{'FN':>6}{'Alertes/1000':>14}")
for s in (0.50, 0.80, 0.90, 0.99):
    rap, prec, vp, fp, fn, a = confusion(s)
    print(f"{s:<7.2f}{rap:>8.3f}{prec:>11.4f}{vp:>6}{fp:>8}{fn:>6}{a:>14.1f}")

precision, rappel, seuils = precision_recall_curve(y_test, proba)
# rappel decroit quand le seuil monte : le DERNIER indice qui atteint encore
# le rappel vise correspond au seuil le plus haut, donc au moins d'alertes.
i = np.where(rappel >= args.rappel)[0][-1]
i = min(i, len(seuils) - 1)
seuil_retenu = float(seuils[i])
rap, prec, vp, fp, fn, a = confusion(seuil_retenu)

print("\nMESURE 9 — seuil retenu")
print("Rappel vise                       :", args.rappel)
print(f"Seuil correspondant               : {seuil_retenu:.6f}")
print(f"Rappel obtenu a ce seuil          : {rap:.3f}")
print(f"Precision a ce seuil              : {prec:.4f}")
print(f"Lesions examinees par maligne     : {round(1 / prec) if prec else 'inf'}")
print(f"Faux negatifs restants            : {fn} (sur {vp + fn} malignes en test)")
print(f"Alertes pour 1000 lesions         : {a:.1f}")

# ---------------------------------------------------------------- 2.5
paquet = {
    "pipeline": modele,
    "version": VERSION,
    "colonnes_attendues": colonnes_attendues,
    "colonnes_numeriques": colonnes_numeriques,
    "colonnes_categorielles": colonnes_categorielles,
    "seuil": seuil_retenu,
    "rappel_cible": args.rappel,
    "metriques": {
        "logistique": m_lr,
        "dummy": m_ref,
        "pr_auc_hasard": float(hasard),
        "au_seuil": {"rappel": rap, "precision": prec, "faux_negatifs": fn,
                     "lesions_par_maligne": round(1 / prec) if prec else None},
    },
    "prevalence_entrainement": float(y_train.mean()),
    "decoupage": {"methode": "GroupShuffleSplit par patient_id",
                  "test_size": args.test, "graine": args.graine},
    "variables_ecartees": {"fuites": FUITES, "identifiants": IDENTIFIANTS,
                           "administratives": ADMINISTRATIVES, "constantes": constantes},
    "versions": {"python": platform.python_version(), "scikit-learn": sklearn.__version__,
                 "pandas": pd.__version__, "numpy": np.__version__, "joblib": joblib.__version__},
    "entraine_le": datetime.now(timezone.utc).isoformat(timespec="seconds"),
}
os.makedirs("model", exist_ok=True)
joblib.dump(paquet, "model/modele.joblib")

print("\nMESURE 10 — paquet produit")
print(f"Taille du fichier         : {os.path.getsize('model/modele.joblib') / 1024:.1f} Ko")
print(f"Colonnes attendues        : {len(colonnes_attendues)}")
print(f"Duree de l'entrainement   : {duree_entrainement:.2f} s")
print("Versions                  :", paquet["versions"])

# Charges utiles pour tester l'API (partie 3) : une vraie ligne du test.
def propre(v):
    if isinstance(v, (float, np.floating)) and np.isnan(v):
        return None
    return v.item() if hasattr(v, "item") else v

ligne_test = {c: propre(v) for c, v in X_test.iloc[0].items()}
with open("charge.json", "w") as f:
    json.dump(ligne_test, f, indent=2)
incomplete = dict(list(ligne_test.items())[: len(ligne_test) // 2])
with open("charge_incomplete.json", "w") as f:
    json.dump(incomplete, f, indent=2)
print("\ncharge.json et charge_incomplete.json ecrits.")

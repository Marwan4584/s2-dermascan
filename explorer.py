"""Partie 1 — Exploration de data/train-metadata.csv.

Ne produit aucun modele : affiche les chiffres des mesures 1 a 5,
a recopier dans EXPLORATION.md.

    python3 explorer.py
"""
import platform

import pandas as pd
import sklearn

CHEMIN = "data/train-metadata.csv"

# Colonnes renseignees APRES le diagnostic (histopathologie, suivi) : fuites.
FUITES = [
    "iddx_full", "iddx_1", "iddx_2", "iddx_3", "iddx_4", "iddx_5",
    "mel_thick_mm", "mel_mitotic_index", "lesion_id",
]

print("=" * 60)
print("MESURE 1 — versions")
print("=" * 60)
print("Python       :", platform.python_version())
print("scikit-learn :", sklearn.__version__)
print("pandas       :", pd.__version__)

# low_memory=False : pandas lit le fichier d'un bloc et deduit un seul type
# par colonne (sinon : avertissements DtypeWarning de type mixte).
d = pd.read_csv(CHEMIN, low_memory=False)

print("\n" + "=" * 60)
print("MESURE 2 — volumetrie et structure")
print("=" * 60)
print("lignes, colonnes :", d.shape)
print("patients distincts :", d["patient_id"].nunique())
tailles = d.groupby("patient_id").size()
print("lesions par patient (min / mediane / max) :",
      tailles.min(), int(tailles.median()), tailles.max())
print("\nTypes des colonnes :")
print(d.dtypes.to_string())

print("\n" + "=" * 60)
print("MESURE 3 — colonnes suspectes de fuite")
print("=" * 60)
total_malignes = int(d["target"].sum())
print(f"(total des malignes dans le jeu : {total_malignes})")
for c in FUITES:
    rempli = d[c].notna().sum()
    malignes = d.loc[d[c].notna(), "target"].sum()
    part = malignes / total_malignes if total_malignes else 0
    print(f"{c:<22} rempli {rempli:>7}  dont malignes {int(malignes):>4}"
          f"  ({part:.0%} des malignes)")

print("\n" + "=" * 60)
print("MESURE 4 — valeurs manquantes et colonnes constantes")
print("=" * 60)
na = d.drop(columns=FUITES).isna().sum()
na = na[na > 0].sort_values(ascending=False)
print("Colonnes avec valeurs manquantes (hors fuites) :")
for c, n in na.items():
    print(f"  {c:<32} {n:>7}  ({n / len(d):.2%})")

constantes = [c for c in d.columns
              if c not in FUITES and d[c].nunique(dropna=True) <= 1]
print("\nColonnes constantes :", constantes)

IDENTIFIANTS = ["isic_id", "patient_id"]
ADMINISTRATIVES = ["attribution", "copyright_license"]
retirees = set(FUITES) | set(IDENTIFIANTS) | set(ADMINISTRATIVES) | set(constantes) | {"target"}
restantes = [c for c in d.columns if c not in retirees]
print(f"\nVariables restantes apres retrait (fuites, identifiants, "
      f"administratives, constantes, cible) : {len(restantes)}")
print("Valeurs de 'attribution' (institutions) :")
print(d["attribution"].value_counts().to_string())

print("\n" + "=" * 60)
print("MESURE 5 — desequilibre de la cible")
print("=" * 60)
pos = int((d["target"] == 1).sum())
neg = int((d["target"] == 0).sum())
print("target = 1 :", pos)
print("target = 0 :", neg)
print(f"taux de positifs : {pos / len(d):.4%}")
print(f"une maligne pour {neg / pos:.0f} benignes")
print(f"exactitude d'un classifieur 'toujours benin' : {neg / len(d):.4%}")

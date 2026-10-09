# TP2 DermaScan — du modèle à l'API d'inférence

Triage des lésions cutanées à partir des métadonnées ISIC 2024 : exploration, pipeline
scikit-learn évalué par patient, API Flask, image Docker publiée dans Azure Container Registry.

## Contenu

| Fichier | Rôle |
|---|---|
| `explorer.py` | Partie 1 : mesures 1 à 5 (volumétrie, fuites, manquantes, déséquilibre) |
| `entrainer.py` | Partie 2 : découpage par patient, pipeline, évaluation, seuil, paquet `model/modele.joblib` |
| `app.py` | Partie 3 : API (`/health`, `/model/info`, `/predict`) |
| `Dockerfile`, `requirements.txt` | Partie 4 : image `dermascan-api:1.0.0`, versions épinglées |
| `tp.sh` | Lance chaque étape et enregistre les résultats dans `captures/` |
| `EXPLORATION.md` | Mesures 1 à 5 et questions 0.1 à 1.5 |
| `MESURES.md` | Mesures 6 à 17 et questions 2.1 à 6.1 |
| `MODEL_CARD.md` | Fiche du modèle, questions 5.1 et 5.2 |
| `captures/` | Sorties brutes de chaque étape |

## Reproduire

```bash
bash tp.sh modele 0.90   # télécharge les données (Kaggle), explore, entraîne
bash tp.sh api           # teste l'API en local
bash tp.sh registre      # crée le registre ACR (une seule fois)
bash tp.sh docker        # construit, teste et publie l'image
bash tp.sh nettoyage     # fin de séance
```

Prérequis : Python 3.11, Docker, Azure CLI, compte Kaggle avec les règles de
`isic-2024-challenge` acceptées. Les données (`data/`, 246 Mo) et le modèle (`model/`) ne
sont pas versionnés : `tp.sh modele` les régénère, avec les mêmes résultats grâce à la graine 42.

## Résultat

Image publiée : `acrdermascankorich.azurecr.io/dermascan-api:1.0.0`
(digest `sha256:d979c792ceb0652b7aff980ffa2be335a207396032392560150b470316ba8ff0`).
Rappel visé 0,90, seuil 0,3476, PR-AUC 0,054 (hasard : 0,0013).

# Image d'inference DermaScan — seance 2.
# PYTHON_VERSION doit correspondre a la version qui a entraine le modele (mesure 1).
ARG PYTHON_VERSION=3.11
FROM python:${PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    MODEL_PATH=model/modele.joblib

WORKDIR /app

# Les dependances d'abord, le code ensuite : la couche pip reste en cache
# tant que requirements.txt ne change pas.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Le modele est un artefact, pas du code : il a sa propre ligne.
COPY model/modele.joblib ./model/
COPY app.py ./

# Utilisateur non privilegie. chmod : les fichiers copies depuis le Mac peuvent
# etre en lecture seule pour leur proprietaire (600) ; appuser doit pouvoir les lire.
RUN chmod -R a+rX /app && useradd --create-home appuser
USER appuser

EXPOSE 8000
# sh -c pour que gunicorn lise la variable PORT (contrat d'interface).
CMD ["sh", "-c", "exec gunicorn -b 0.0.0.0:${PORT} --workers 2 --timeout 120 app:app"]

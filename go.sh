#!/usr/bin/env bash
# Une seule commande pour finir la partie 4 : bash ~/s2-dermascan/go.sh
cd "$(dirname "$0")"
mkdir -p captures
exec > >(tee captures/go.log) 2>&1

[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

if ! docker info >/dev/null 2>&1; then
  echo ">> Docker ne repond pas : ouverture de Docker Desktop, attente..."
  open -a Docker
  for _ in $(seq 90); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || { echo "ECHEC : Docker Desktop ne demarre pas."; exit 1; }
fi
echo ">> Docker OK"

# Azure CLI : on n'utilise pas Homebrew (Command Line Tools trop anciennes sur ce Mac).
# On l'installe avec pip dans un environnement Python a part, ~/.azcli.
export PATH="$HOME/.azcli/bin:$PATH"
if ! command -v az >/dev/null; then
  echo ">> Azure CLI absent : installation avec pip dans ~/.azcli (5 a 10 minutes)..."
  echo ">> Espace libre : $(df -h ~ | awk 'NR==2{print $4}') (il faut environ 1 Go)"
  /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 -m venv "$HOME/.azcli" 2>/dev/null || python3 -m venv "$HOME/.azcli"
  "$HOME/.azcli/bin/pip" install -q --upgrade pip
  # --only-binary : interdit la compilation (cryptography demande Rust + OpenSSL, absents ici).
  "$HOME/.azcli/bin/pip" install -q --prefer-binary --only-binary=cryptography,cffi,psutil azure-cli \
    || { echo "ECHEC : installation azure-cli avec pip."; echo "=> Plan B : voir le message de Claude (docker login avec les cles d'acces du registre)."; rm -rf "$HOME/.azcli"; exit 1; }
fi
echo ">> $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null | sed 's/^/Azure CLI /')"

if [ -n "$ACR_NAME" ] && ! command -v az >/dev/null; then
  echo ">> Plan B : pas d'Azure CLI, publication avec docker login deja fait sur $ACR_NAME"
elif ! az account show >/dev/null 2>&1; then
  echo ">> Connexion Azure : une page va s'ouvrir dans le navigateur."
  az login >/dev/null || { echo "ECHEC : az login."; exit 1; }
fi
command -v az >/dev/null && echo ">> Azure connecte : $(az account show --query name -o tsv)"

bash lancer_partie_4.sh
echo ">> FIN go.sh (code $?)"

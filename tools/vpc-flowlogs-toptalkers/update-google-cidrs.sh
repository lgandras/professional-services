#!/usr/bin/env bash

set -e

DIR=$(dirname $0)
VIRTUALENV=$(command -v virtualenv)
PYTHON3=$(command -v python3)

if [[ "" = "${VIRTUALENV}" ]]; then
  echo "virtualenv is required to install google-cidrs." >&2
  return 1
fi

if [[ "" = "${PYTHON3}" ]]; then
  echo "python3 is required to install google-cidrs." >&2
  return 1
fi

if [[ ! -d "${DIR}/google-cidrs/venv" ]]; then
  virtualenv -p "${PYTHON3}" "${DIR}/google-cidrs/venv"
fi

source "${DIR}/google-cidrs/venv/bin/activate"
pip install -r "${DIR}/google-cidrs/requirements.txt"
python "${DIR}/google-cidrs/main.py" > "${DIR}/google-cidrs.yaml"

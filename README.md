# Pre-requisites
- Pyenv
- Poetry
- GreatSPN

# Structure
- generated_ocpn => PNG image for the mined object-centric petri nets, 1 per event log
- generated_uncolored_pn => PNG image for the mined uncolored petri nets, 1 per object type
- generated_pnml => Exported uncolored petri nets, 1 per object type
- greatspn => GreatSPN projects with imported PNML and CTL Properties, 1 per event log

# Execution Steps
```sh
pyenv install 3.11
poetry env use 3.11
poetry install 
poetry run python ddia_analyzer/ocel2.py
```

# Performance Boost - Mac
```sh
brew install openblas
export OPENBLAS_NUM_THREADS=8
export OMP_NUM_THREADS=8
```

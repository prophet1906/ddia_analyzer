# OCEL 2.0 Petri Net Miner

A Python module for discovering Object-Centric Petri Nets (OCPNs) from OCEL 2.0 event logs using PM4Py.

## Overview

This module processes Object-Centric Event Log (OCEL 2.0) files and discovers Petri nets for each object type using the Inductive Miner algorithm. It also computes log-model evaluation metrics and performs WF-net soundness analysis.

## Installation

### Using Docker (Recommended)

```bash
# Build the Docker image
docker build -t miner:latest -f Dockerfile .

# Run the miner
docker run -v $(pwd)/../data:/app/data:ro \
           -v $(pwd)/../generated_pnml:/app/generated_pnml \
           -v $(pwd)/../generated_ocpn:/app/generated_ocpn \
           -v $(pwd)/../generated_uncolored_pn:/app/generated_uncolored_pn \
           miner:latest /app/data/ocel2-p2p.json -n procure-to-pay
```

### Using Poetry (Local Development)

```bash
# Install dependencies
poetry install

# Run the miner
poetry run python -m miner.ocel2 /path/to/ocel.json -n scenario-name
```

## Command Line Interface

```
usage: ocel2.py [-h] [-n NAME] input_file

Process OCEL2 JSON/XML files and discover Object-Centric Petri Nets

positional arguments:
  input_file            Path to the OCEL2 JSON or XML file

optional arguments:
  -h, --help            show this help message and exit
  -n NAME, --name NAME  Scenario name for output files (defaults to input 
                        filename without extension)
```

### Examples

```bash
# Basic usage with auto-generated scenario name
python -m miner.ocel2 data/ocel2-p2p.json

# Custom scenario name
python -m miner.ocel2 data/ocel2-p2p.json -n procure-to-pay

# Process XML format
python -m miner.ocel2 data/events.xml -n my-scenario
```

## API Reference

### Module: `miner.ocel2`

#### Functions

##### `ensure_output_dirs()`
Creates the required output directories if they don't exist.

**Output Directories:**
- `generated_pnml/` - PNML files for each object type
- `generated_ocpn/` - Object-Centric Petri Net visualization (PNG)
- `generated_uncolored_pn/` - Individual Petri Net visualizations (PNG)

---

##### `export_pnml(filename, net, initial_marking, final_marking)`
Exports a Petri net to PNML format with GreatSPN-compatible XML namespace.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `filename` | `str` | Output filename (without extension) |
| `net` | `PetriNet` | PM4Py Petri net object |
| `initial_marking` | `Marking` | Initial marking of the net |
| `final_marking` | `Marking` | Final marking of the net |

**Output:**
- Creates `generated_pnml/{filename}.pnml`
- Fixes PNML namespace for GreatSPN compatibility

---

##### `get_stats(scenario, ocel)`
Main analysis function that discovers OCPNs and computes all metrics.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `scenario` | `str` | Scenario name for output files |
| `ocel` | `OCEL` | PM4Py OCEL object loaded from JSON/XML |

**Outputs:**
1. **Console Output:**
   - Event log statistics (#events, #objects, #relations)
   - Discovery time and memory usage
   - For each object type:
     - Petri net structure (#places, #transitions, #arcs)
     - Fitness (token-based replay and alignments)
     - Generalization score
     - Simplicity score
     - WF-net soundness analysis (WOFLAN)

2. **Generated Files:**
   - `generated_ocpn/{scenario}.png` - OCPN visualization
   - `generated_pnml/{scenario}_{object_type}.pnml` - Per-object PNML
   - `generated_uncolored_pn/{scenario}-{object_type}.png` - Per-object visualization

---

##### `parse_args()`
Parses command-line arguments.

**Returns:** `argparse.Namespace` with:
- `input_file` - Path to OCEL file
- `name` - Optional scenario name

## Output File Formats

### PNML Files
Standard Petri Net Markup Language format compatible with:
- GreatSPN
- PIPE
- Other PNML-compliant tools

The module automatically adds the correct XML namespace for GreatSPN compatibility:
```xml
<pnml xmlns="http://www.pnml.org/version-2009/grammar/pnml">
```

### Metrics Output

The console output includes the following metrics for each object type:

| Metric | Description | Range |
|--------|-------------|-------|
| **Fitness (Token Replay)** | How well the model replays the log | 0.0 - 1.0 |
| **Fitness (Alignments)** | Alignment-based fitness | 0.0 - 1.0 |
| **Generalization** | Model generalization beyond observed behavior | 0.0 - 1.0 |
| **Simplicity** | Structural simplicity of the Petri net | 0.0 - 1.0 |
| **WF-net Soundness** | Whether the net is a sound workflow net | True/False |

## Dependencies

- **pm4py** >= 2.7.15.2 - Process mining library
- **Python** >= 3.10

## Architecture

```
miner/
├── Dockerfile          # Docker build configuration
├── pyproject.toml      # Poetry dependency management
├── README.md           # This documentation
└── miner/
    ├── __init__.py     # Package initialization
    └── ocel2.py        # Main mining module
```

## Supported Input Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| OCEL 2.0 JSON | `.json` | JSON format per OCEL 2.0 specification |
| OCEL 2.0 XML | `.xml` | XML format per OCEL 2.0 specification |

## Algorithm Details

The miner uses PM4Py's Object-Centric Petri Net discovery algorithm:

1. **OCEL Loading**: Reads OCEL 2.0 JSON/XML files
2. **OCPN Discovery**: Applies the discovery algorithm from [van der Aalst & Berti, 2020]
3. **Flattening**: For each object type, flattens the OCEL to a traditional event log
4. **Metric Computation**: Computes fitness, precision, generalization, simplicity
5. **Soundness Analysis**: Runs WOFLAN algorithm to verify WF-net properties
6. **Export**: Generates PNML files and PNG visualizations

## References

- [OCEL 2.0 Standard](https://www.ocel-standard.org/)
- [PM4Py Documentation](https://pm4py.fit.fraunhofer.de/)
- van der Aalst, W.M.P., Berti, A.: Discovering Object-centric Petri Nets. Fundamenta Informaticae 175(1-4), 1-40 (2020)
- Leemans, S.J.J., Fahland, D., van der Aalst, W.M.P.: Discovering Block-Structured Process Models from Event Logs - A Constructive Approach. Petri Nets 2013

## License

MIT License - See [LICENSE](../LICENSE) for details.

import os
import gc
import tracemalloc
import time
import argparse
import pm4py
import logging
from pathlib import Path
from pm4py.algo.evaluation.generalization import algorithm as generalization_evaluator
from pm4py.algo.evaluation.simplicity import algorithm as simplicity_evaluator
from pm4py.algo.analysis.woflan import algorithm as woflan
# from pm4py.statistics.variants.log import get as variants_module
# from pm4py.algo.simulation.playout.petri_net import algorithm as simulator
# from pm4py.algo.evaluation.earth_mover_distance import algorithm as emd_evaluator

logger = logging.getLogger("miner.ocel2")
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")

console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(formatter)

logger.addHandler(console_handler)


def ensure_output_dirs():
    logger.info("Ensuring all output directories exist")
    Path("generated_pnml").mkdir(parents=True, exist_ok=True)
    Path("generated_ocpn").mkdir(parents=True, exist_ok=True)
    Path("generated_uncolored_pn").mkdir(parents=True, exist_ok=True)


def export_pnml(filename, net, initial_marking, final_marking):
    path = f"generated_pnml/{filename}.pnml"
    pm4py.write_pnml(net, initial_marking, final_marking, path)
    logger.info(f"Exported {path}")
    __fix_pnml_type(path)


def __fix_pnml_type(path: str):
    try:
        with open(path, "r") as file:
            content = file.read()
    except FileNotFoundError:
        logger.error(f"Error: File '{path}' not found.")
        return

    modified_content = content.replace(
        "<pnml>", '<pnml xmlns="http://www.pnml.org/version-2009/grammar/pnml">'
    )
    modified_content = modified_content.replace(
        "http://www.pnml.org/version-2009/grammar/pnmlcoremodel",
        "http://www.pnml.org/version-2009/grammar/ptnet",
    )

    with open(path, "w") as file:
        file.write(modified_content)


def get_stats(scenario, ocel):
    gc.collect()  # Force Garbage Collection
    logger.info("=" * 30)
    logger.info(scenario)
    logger.info(f"#events = {len(ocel.events)}")
    logger.info(f"#objects = {len(ocel.objects)}")
    logger.info(f"#relations = {len(ocel.relations)}")
    discovery_start_time = time.perf_counter()
    tracemalloc.start()  # Start Tracing Memory Allocations
    ocpn = pm4py.discover_oc_petri_net(ocel)
    discovery_end_time = time.perf_counter()
    current_memory, peak_memory = tracemalloc.get_traced_memory()
    tracemalloc.stop()  # Stop Tracing Memory Allocations
    logger.info(f"Current memory: {current_memory / (1024 * 1024):.2f} MiB")
    logger.info(
        f"Peak memory usage between timestamps: {peak_memory / (1024 * 1024):.2f} MiB"
    )
    logger.info(
        f"Time taken for OCPN discovery: {discovery_end_time - discovery_start_time:.6f} seconds"
    )
    scenario_pn_path = f"generated_ocpn/{scenario}.png"
    pm4py.save_vis_ocpn(ocpn, scenario_pn_path)
    logger.info(f"Exported {scenario}")
    # object_types = pm4py.ocel_get_object_types(ocel)
    for o in ocpn["object_types"]:
        # export pnml
        export_pnml(
            f"{scenario}_{o}",
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
        )
        pm4py.save_vis_petri_net(
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
            f"generated_uncolored_pn/{scenario}-{o}.png",
        )
        places = ocpn["petri_nets"][o][0].places
        transitions = ocpn["petri_nets"][o][0].transitions
        arcs = ocpn["petri_nets"][o][0].arcs
        logger.info("-" * 30)
        logger.info(o)
        logger.info("-" * 30)
        logger.info(f"#places = {len(places)}")
        logger.info(f"#transitions = {len(transitions)}")
        logger.info(f"#arcs = {len(arcs)}")
        log = pm4py.ocel_flattening(ocel, o)
        # fitness
        fitness_1 = pm4py.fitness_token_based_replay(
            log,
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
        )
        logger.info(f"fitness: token based replay = {fitness_1}")
        fitness_2 = pm4py.fitness_alignments(
            log,
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
        )
        logger.info(f"fitness: alignments = {fitness_2}")
        # precision
        # precision_1 = pm4py.precision_token_based_replay(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        # logger.info(f"precision: token based replay = {precision_1}")
        # precision_2 = pm4py.precision_alignments(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        # logger.info(f"precision: alignments = {precision_2}")
        # generalization
        generalization = generalization_evaluator.apply(
            log,
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
        )
        logger.info(f"generalization = {generalization}")
        # simplicity
        simplicity = simplicity_evaluator.apply(ocpn["petri_nets"][o][0])
        logger.info(f"simplicity = {simplicity}")
        # WF-net analysis
        is_sound, dictio_diagnostics = woflan.apply(
            ocpn["petri_nets"][o][0],
            ocpn["petri_nets"][o][1],
            ocpn["petri_nets"][o][2],
            parameters={
                woflan.Parameters.RETURN_ASAP_WHEN_NOT_SOUND: False,
                woflan.Parameters.PRINT_DIAGNOSTICS: False,
                woflan.Parameters.RETURN_DIAGNOSTICS: True,
            },
        )
        logger.info(f"WF-net is_sound = {is_sound}")
        for output in dictio_diagnostics.keys():
            logger.info(f"WOFLAN {output} = {dictio_diagnostics[output]}")

        # Earth Mover Distance only relevant for stochastic conformance checking
        # Stochastic playout simulation may get stuck
        # log_language = variants_module.get_language(log)
        # playout_log = simulator.apply(
        #     ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2],
        #     parameters={simulator.Variants.STOCHASTIC_PLAYOUT.value.Parameters.LOG: log},
        #     variant=simulator.Variants.STOCHASTIC_PLAYOUT
        # )
        # model_language = variants_module.get_language(playout_log)
        # emd = emd_evaluator.apply(model_language, log_language)
        # logger.info(f"earth mover distance = {emd}", emd)
    logger.info("=" * 30)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Process OCEL2 JSON/XML files and discover Object-Centric Petri Nets"
    )
    parser.add_argument(
        "input_file", type=str, help="Path to the OCEL2 JSON or XML file"
    )
    parser.add_argument(
        "-n",
        "--name",
        type=str,
        default=None,
        help="Scenario name for output files (defaults to input filename without extension)",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    input_path = args.input_file
    if not os.path.exists(input_path):
        logger.error(f"Input file not found: {input_path}")
        exit(1)

    # Determine scenario name
    if args.name:
        scenario_name = args.name
    else:
        scenario_name = Path(input_path).stem

    ensure_output_dirs()

    # Read OCEL file based on extension
    file_ext = Path(input_path).suffix.lower()
    if file_ext == ".json":
        ocel = pm4py.read_ocel2_json(input_path)
    elif file_ext == ".xml":
        ocel = pm4py.read_ocel2_xml(input_path)
    else:
        logger.error(
            f"Unsupported file format: {file_ext}. Supported formats: .json, .xml"
        )
        exit(1)

    get_stats(scenario_name, ocel)

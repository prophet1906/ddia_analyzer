import os
import pm4py
import logging
from pathlib import Path
from pm4py.algo.evaluation.generalization import algorithm as generalization_evaluator
from pm4py.algo.evaluation.simplicity import algorithm as simplicity_evaluator
from pm4py.algo.analysis.woflan import algorithm as woflan
# from pm4py.statistics.variants.log import get as variants_module
# from pm4py.algo.simulation.playout.petri_net import algorithm as simulator
# from pm4py.algo.evaluation.earth_mover_distance import algorithm as emd_evaluator

logger = logging.getLogger("ddia_analyzer")
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')

result_dir = "results.txt"
if os.path.exists(result_dir):
    os.remove(result_dir)

file_handler = logging.FileHandler('results.txt')
file_handler.setLevel(logging.DEBUG)
file_handler.setFormatter(formatter)

console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(formatter)

logger.addHandler(file_handler)
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
        with open(path, 'r') as file:
            content = file.read()
    except FileNotFoundError:
        logger.error(f"Error: File '{path}' not found.")
        return

    modified_content = content.replace(
        "<pnml>", "<pnml xmlns=\"http://www.pnml.org/version-2009/grammar/pnml\">")
    modified_content = modified_content.replace(
        "http://www.pnml.org/version-2009/grammar/pnmlcoremodel", "http://www.pnml.org/version-2009/grammar/ptnet")

    with open(path, 'w') as file:
        file.write(modified_content)

def get_stats(scenario, ocel):
    logger.info("=" * 30)
    logger.info(scenario)
    ocpn = pm4py.discover_oc_petri_net(ocel)
    scenario_pn_path = f"generated_ocpn/{scenario}.png"
    pm4py.save_vis_ocpn(ocpn, scenario_pn_path)
    logger.info(f"Exported {scenario}")
    object_types = pm4py.ocel_get_object_types(ocel)
    for o in ocpn["object_types"]:
        # export pnml
        export_pnml(f"{scenario}_{o}", ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        pm4py.save_vis_petri_net(ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2], f"generated_uncolored_pn/{scenario}-{o}.png")
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
        fitness_1 = pm4py.fitness_token_based_replay(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        logger.info(f"fitness: token based replay = {fitness_1}")
        fitness_2 = pm4py.fitness_alignments(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        logger.info(f"fitness: alignments = {fitness_2}")
        # precision
        precision_1 = pm4py.precision_token_based_replay(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        logger.info(f"precision: token based replay = {precision_1}")
        precision_2 = pm4py.precision_alignments(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        logger.info(f"precision: alignments = {precision_2}")
        # generalization
        generalization = generalization_evaluator.apply(log, ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2])
        logger.info(f"generalization = {generalization}")
        # simplicity
        simplicity = simplicity_evaluator.apply(ocpn["petri_nets"][o][0])
        logger.info(f"simplicity = {simplicity}")
        # WF-net analysis
        is_sound, dictio_diagnostics = woflan.apply(
            ocpn["petri_nets"][o][0], ocpn["petri_nets"][o][1], ocpn["petri_nets"][o][2],
            parameters={
                woflan.Parameters.RETURN_ASAP_WHEN_NOT_SOUND: False,
                woflan.Parameters.PRINT_DIAGNOSTICS: False,
                woflan.Parameters.RETURN_DIAGNOSTICS: True
            }
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

if __name__ == "__main__":
    ensure_output_dirs()

    # Container Logistics
    container_logistics_ocel_path = os.path.join("ocel2_samples", "8428084", "ContainerLogistics.json")
    container_logistics_ocel = pm4py.read_ocel2_json(container_logistics_ocel_path)
    get_stats("container-logistics", container_logistics_ocel)

    # Procure-to-Pay
    p2p_ocel_path = os.path.join("ocel2_samples", "8412920", "ocel2-p2p.json")
    p2p_ocel = pm4py.read_ocel2_json(p2p_ocel_path)
    get_stats("procure-to-pay", p2p_ocel)

    # Order Management
    order_management_ocel_path = os.path.join("ocel2_samples", "8428112", "order-management.json")
    order_management_ocel = pm4py.read_ocel2_json(order_management_ocel_path)
    get_stats("order-management", order_management_ocel)

    # LRM Order-to-Cash
    order_to_cash_ocel_path = os.path.join("ocel2_samples", "13879980", "01_o2c.xml")
    order_to_cash_ocel = pm4py.read_ocel2_xml(order_to_cash_ocel_path)
    get_stats("lrm-order-to-cash", order_to_cash_ocel)

    # LRM Procure-to-Pay
    p2p_v1_path = os.path.join("ocel2_samples", "13879980", "02_p2p.xml")
    p2p_v1_ocel = pm4py.read_ocel2_xml(p2p_v1_path)
    get_stats("lrm-procure-to-pay", p2p_v1_ocel)

    # LRM Hiring
    hiring_ocel_path = os.path.join("ocel2_samples", "13879980", "03_hiring.xml")
    hiring_ocel = pm4py.read_ocel2_xml(hiring_ocel_path)
    get_stats("lrm-hiring", hiring_ocel)

    # LRM Hospital Patient
    hospital_ocel_path = os.path.join("ocel2_samples", "13879980", "04_hospital.xml")
    hospital_ocel = pm4py.read_ocel2_xml(hospital_ocel_path)
    get_stats("lrm-hospital-patient", hospital_ocel)
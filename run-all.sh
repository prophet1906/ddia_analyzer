#!/bin/bash
#
# COORDINATION 2026 - Artefact Evaluation Script
# Formal Verification of Distributed Data-Intensive Microservice Applications using Petri Nets
#
# This script provides push-button evaluation for all functional outcomes (F1-F5)
# described in the AE appendix.
#
# Usage: ./run-all.sh [OPTIONS]
#
# Options:
#   --quick       Run quick sanity check only (F1 on P2P dataset)
#   --all         Run all functional evaluations (default)
#   --clean       Clean generated outputs before running
#   --help        Show this help message
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output directories
PNML_DIR="generated_pnml"
OCPN_DIR="generated_ocpn"
UNCOLORED_DIR="generated_uncolored_pn"
RESULTS_FILE="evaluation_results.txt"

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_help() {
    echo "COORDINATION 2026 - Artefact Evaluation Script"
    echo ""
    echo "Usage: ./run-all.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quick       Run quick sanity check only (F1 on P2P dataset)"
    echo "  --all         Run all functional evaluations (default)"
    echo "  --clean       Clean generated outputs before running"
    echo "  --help        Show this help message"
    echo ""
    echo "Functional Outcomes:"
    echo "  F1: Petri Net Mining from OCEL Logs"
    echo "  F2: Log-Model Evaluation Metrics"
    echo "  F3: WF-net Soundness Analysis"
    echo "  F4: CTL Model Checking instructions (requires GreatSPN)"
    echo "  F5: Saga Implementation analysis"
    echo ""
    echo "Estimated Time:"
    echo "  --quick: ~5 minutes"
    echo "  --all:   ~15-20 minutes"
    echo ""
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Docker
    if command -v docker &> /dev/null; then
        print_success "Docker is installed: $(docker --version)"
    else
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check data files
    if [ -f "data/ocel2-p2p.json" ]; then
        print_success "P2P dataset found: data/ocel2-p2p.json"
    else
        print_error "P2P dataset not found. Please ensure data/ocel2-p2p.json exists."
        exit 1
    fi
    
    if [ -f "data/ContainerLogistics.json" ]; then
        print_success "Container Logistics dataset found"
    else
        print_warning "Container Logistics dataset not found (optional)"
    fi
    
    if [ -f "data/order-management.json" ]; then
        print_success "Order Management dataset found"
    else
        print_warning "Order Management dataset not found (optional)"
    fi
}

clean_outputs() {
    print_header "Cleaning Previous Outputs"
    
    rm -rf "$PNML_DIR" "$OCPN_DIR" "$UNCOLORED_DIR"
    rm -f "$RESULTS_FILE"
    
    print_success "Cleaned output directories"
}

build_miner() {
    print_header "Building Miner Docker Image"
    
    print_info "Building miner:latest..."
    docker build -t miner:latest -f miner/Dockerfile miner/ 2>&1 | tail -5
    
    print_success "Miner Docker image built successfully"
}

run_miner() {
    local input_file=$1
    local scenario_name=$2
    local description=$3
    
    print_info "Processing: $description"
    print_info "Input: $input_file"
    print_info "Scenario: $scenario_name"
    
    # Create output directories
    mkdir -p "$PNML_DIR" "$OCPN_DIR" "$UNCOLORED_DIR"
    
    # Run miner
    docker run --rm \
        -v "$(pwd)/data:/app/data:ro" \
        -v "$(pwd)/$PNML_DIR:/app/generated_pnml" \
        -v "$(pwd)/$OCPN_DIR:/app/generated_ocpn" \
        -v "$(pwd)/$UNCOLORED_DIR:/app/generated_uncolored_pn" \
        miner:latest "/app/data/$input_file" -n "$scenario_name" 2>&1 | tee -a "$RESULTS_FILE"
    
    # Count generated files
    local pnml_count=$(ls -1 "$PNML_DIR"/${scenario_name}_*.pnml 2>/dev/null | wc -l)
    
    if [ "$pnml_count" -gt 0 ]; then
        print_success "Generated $pnml_count PNML files for $scenario_name"
    else
        print_warning "No PNML files generated for $scenario_name"
    fi
    
    echo ""
}

verify_f1_f2_f3() {
    print_header "Verifying F1, F2, F3: Petri Net Mining and Metrics"
    
    # Check PNML files exist
    print_info "Checking generated PNML files..."
    
    local expected_p2p_objects=("invoice_receipt" "purchase_requisition" "purchase_order" "goods_receipt" "payment" "material" "quotation")
    local found=0
    local missing=0
    
    for obj in "invoice receipt" "purchase_requisition" "purchase_order" "goods receipt" "payment" "material" "quotation"; do
        # Handle spaces in filenames
        if ls "$PNML_DIR"/procure-to-pay_*"$obj"*.pnml 1> /dev/null 2>&1 || \
           ls "$PNML_DIR"/procure-to-pay_$(echo "$obj" | tr ' ' '_')*.pnml 1> /dev/null 2>&1; then
            ((found++))
        else
            print_warning "Missing PNML for object type: $obj"
            ((missing++))
        fi
    done
    
    print_info "Found $found PNML files for P2P dataset"
    
    # Check metrics in results
    if grep -q "is_sound = True" "$RESULTS_FILE" 2>/dev/null; then
        print_success "F3 VERIFIED: WF-net soundness confirmed (is_sound = True found in output)"
    else
        print_warning "F3: Could not verify WF-net soundness in output"
    fi
    
    if grep -q "fitness" "$RESULTS_FILE" 2>/dev/null; then
        print_success "F2 VERIFIED: Fitness metrics computed"
    fi
    
    if grep -q "generalization" "$RESULTS_FILE" 2>/dev/null; then
        print_success "F2 VERIFIED: Generalization metrics computed"
    fi
    
    if grep -q "simplicity" "$RESULTS_FILE" 2>/dev/null; then
        print_success "F2 VERIFIED: Simplicity metrics computed"
    fi
    
    if [ "$found" -gt 0 ]; then
        print_success "F1 VERIFIED: Petri nets mined and exported to PNML"
    fi
}

print_f4_instructions() {
    print_header "F4: CTL Model Checking Instructions"
    
    echo "To verify the duplicate payment bug (F4), follow these steps in GreatSPN:"
    echo ""
    echo "1. Open GreatSPN and load the project:"
    echo "   File -> Open Project -> greatspn/COORDINATION 2026.PNPRO"
    echo ""
    echo "2. Or import the generated PNML file:"
    echo "   File -> Import -> Import PNML file..."
    echo "   Select: $PNML_DIR/procure-to-pay_invoice receipt.pnml"
    echo ""
    echo "3. Open the CTL model checking solution:"
    echo "   COORDINATION 2026-CTL model checking of P2P Invoice Receipt.solution"
    echo ""
    echo "4. In the Measures panel, enter the CTL formula:"
    echo "   AG(en(Execute_Payment) -> AG(!en(Execute_Payment)))"
    echo ""
    echo "5. Click 'Compute' to run the model checker"
    echo ""
    echo "Expected Result: Formula evaluates to FALSE with a counterexample trace"
    echo "showing the duplicate payment bug (see paper Figure 5)."
    echo ""
    
    if [ -f "greatspn/COORDINATION 2026.PNPRO" ]; then
        print_success "GreatSPN project file exists: greatspn/COORDINATION 2026.PNPRO"
    else
        print_warning "GreatSPN project file not found"
    fi
}

print_f5_instructions() {
    print_header "F5: Saga Implementation Verification"
    
    echo "The Saga example verification can be done in two ways:"
    echo ""
    echo "Option A: Use pre-generated GreatSPN solution"
    echo "  1. Open: greatspn/COORDINATION 2026-CTL model checking of SAGA Debezium + OCEL Connector.solution"
    echo "  2. Run the CTL formula verification"
    echo ""
    echo "Option B: Generate fresh OCEL logs (requires ~45 minutes)"
    echo "  Follow the detailed instructions in README.md Section 'Option 2'"
    echo ""
    
    if [ -d "greatspn/COORDINATION 2026-CTL model checking of SAGA Debezium + OCEL Connector.solution" ]; then
        print_success "Saga GreatSPN solution exists"
    fi
}

compare_with_reported() {
    print_header "Comparing with Reported Results"
    
    if [ -f "reported_results/analysis_results_published.txt" ]; then
        print_info "Reported results available in: reported_results/analysis_results_published.txt"
        print_info "Generated results saved to: $RESULTS_FILE"
        echo ""
        echo "You can compare the metrics manually or use diff:"
        echo "  diff $RESULTS_FILE reported_results/analysis_results_published.txt"
        echo ""
        print_success "Pre-computed results available for comparison"
    else
        print_warning "Reported results file not found"
    fi
}

print_summary() {
    print_header "Evaluation Summary"
    
    echo "Generated Outputs:"
    echo "  - PNML files:        $PNML_DIR/"
    echo "  - OCPN visualizations: $OCPN_DIR/"
    echo "  - Petri net images:  $UNCOLORED_DIR/"
    echo "  - Results log:       $RESULTS_FILE"
    echo ""
    
    # Count outputs
    local pnml_count=$(ls -1 "$PNML_DIR"/*.pnml 2>/dev/null | wc -l)
    local png_count=$(ls -1 "$OCPN_DIR"/*.png "$UNCOLORED_DIR"/*.png 2>/dev/null | wc -l)
    
    echo "Statistics:"
    echo "  - Total PNML files generated: $pnml_count"
    echo "  - Total PNG visualizations:   $png_count"
    echo ""
    
    echo "Functional Outcomes Status:"
    echo "  F1 (Petri Net Mining):     $([ $pnml_count -gt 0 ] && echo '✓ VERIFIED' || echo '✗ NOT VERIFIED')"
    echo "  F2 (Evaluation Metrics):   $(grep -q 'fitness' $RESULTS_FILE 2>/dev/null && echo '✓ VERIFIED' || echo '✗ NOT VERIFIED')"
    echo "  F3 (WF-net Soundness):     $(grep -q 'is_sound = True' $RESULTS_FILE 2>/dev/null && echo '✓ VERIFIED' || echo '✗ NOT VERIFIED')"
    echo "  F4 (CTL Model Checking):   → Manual verification in GreatSPN required"
    echo "  F5 (Saga Verification):    → Manual verification in GreatSPN required"
    echo ""
    
    print_success "Automated evaluation complete!"
    echo ""
    echo "Next Steps:"
    echo "  1. Review generated PNML files in $PNML_DIR/"
    echo "  2. Open GreatSPN to verify F4 and F5 (see instructions above)"
    echo "  3. Compare metrics with reported_results/analysis_results_published.txt"
}

# Main execution
main() {
    local mode="all"
    local clean=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                mode="quick"
                shift
                ;;
            --all)
                mode="all"
                shift
                ;;
            --clean)
                clean=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_header "COORDINATION 2026 - Artefact Evaluation"
    echo "Mode: $mode"
    echo "Clean: $clean"
    echo "Start time: $(date)"
    
    # Clean if requested
    if [ "$clean" = true ]; then
        clean_outputs
    fi
    
    # Run evaluation
    check_prerequisites
    build_miner
    
    case $mode in
        quick)
            print_header "Running Quick Evaluation (P2P Dataset Only)"
            run_miner "ocel2-p2p.json" "procure-to-pay" "Procure-to-Pay (P2P) Dataset"
            ;;
        all)
            print_header "Running Full Evaluation (All Datasets)"
            
            # F1, F2, F3: Process all datasets
            run_miner "ocel2-p2p.json" "procure-to-pay" "Procure-to-Pay (P2P) Dataset"
            
            if [ -f "data/ContainerLogistics.json" ]; then
                run_miner "ContainerLogistics.json" "container-logistics" "Container Logistics Dataset"
            fi
            
            if [ -f "data/order-management.json" ]; then
                run_miner "order-management.json" "order-management" "Order Management Dataset"
            fi
            ;;
    esac
    
    # Verify results
    verify_f1_f2_f3
    
    # Print manual instructions for F4 and F5
    print_f4_instructions
    print_f5_instructions
    
    # Compare with reported results
    compare_with_reported
    
    # Print summary
    print_summary
    
    echo "End time: $(date)"
}

# Run main function
main "$@"

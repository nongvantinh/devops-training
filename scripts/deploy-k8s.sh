#!/bin/bash

# CoffeeShop Kubernetes Deployment Script
# This script deploys the application to Kubernetes (EKS)

set -e

source "$(dirname "$0")/common/utils.sh"

NAMESPACE="coffeeshop"
MONITORING_NAMESPACE="monitoring"
AWS_REGION="us-west-2"
SCRIPT_DIR="$(get_script_dir)"
KUBERNETES_DIR="${SCRIPT_DIR}/../kubernetes"
MONITORING_DIR="${SCRIPT_DIR}/../monitoring"

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command_exists kubectl; then
        error "kubectl is not installed. Please install kubectl first."
    fi
    
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl is not configured or cluster is not accessible. Run: aws eks update-kubeconfig --region ${AWS_REGION} --name <cluster-name>"
    fi
    
    if ! kubectl get nodes &> /dev/null; then
        error "Cannot access Kubernetes cluster nodes. Please check your EKS configuration."
    fi
    
    if [ ! -d "${KUBERNETES_DIR}" ]; then
        error "Kubernetes manifests directory not found: ${KUBERNETES_DIR}"
    fi
    
    if [ ! -d "${MONITORING_DIR}" ]; then
        warn "Monitoring directory not found: ${MONITORING_DIR}. Monitoring deployment will be skipped."
    fi
    
    log "Prerequisites check passed!"
}

create_namespaces() {
    log "Creating namespaces..."
    
    # Use the existing namespace.yaml file if it exists
    if [ -f "${KUBERNETES_DIR}/namespace.yaml" ]; then
        log "Applying namespace configuration from namespace.yaml..."
        kubectl apply -f "${KUBERNETES_DIR}/namespace.yaml"
    else
        # Fallback to manual namespace creation
        kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
        kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    kubectl wait --for=condition=Active namespace/${NAMESPACE} --timeout=60s
    kubectl wait --for=condition=Active namespace/${MONITORING_NAMESPACE} --timeout=60s
    
    log "Namespaces created successfully!"
}

deploy_secrets_and_configs() {
    log "Deploying secrets and configmaps..."
    
    # Apply secrets first if they exist
    if [ -f "${KUBERNETES_DIR}/secrets.yaml" ]; then
        log "Applying secrets.yaml..."
        kubectl apply -f "${KUBERNETES_DIR}/secrets.yaml"
    else
        warn "secrets.yaml not found, skipping secrets deployment..."
    fi
    
    if [ -f "${KUBERNETES_DIR}/configmaps.yaml" ]; then
        log "Applying configmaps.yaml..."
        kubectl apply -f "${KUBERNETES_DIR}/configmaps.yaml"
    else
        warn "configmaps.yaml not found, skipping configmaps deployment..."
    fi
    
    sleep 5
    
    log "Secrets and configmaps deployed successfully!"
}

deploy_storage() {
    log "Deploying storage resources..."
    
    if [ -d "${KUBERNETES_DIR}/storage" ]; then
        kubectl apply -f "${KUBERNETES_DIR}/storage/"
        log "Storage resources deployed successfully!"
    else
        warn "Storage directory not found, skipping storage deployment..."
    fi
}

deploy_infrastructure_services() {
    log "Deploying infrastructure services (PostgreSQL, RabbitMQ)..."
    
    # Deploy infrastructure services in order with proper dependency handling
    local infra_services=("postgres" "rabbitmq")
    
    for service in "${infra_services[@]}"; do
        local deployment_file="${KUBERNETES_DIR}/deployments/${service}.yaml"
        
        if [ -f "${deployment_file}" ]; then
            log "Deploying ${service}..."
            kubectl apply -f "${deployment_file}"
            
            # Wait for deployment to be available with extended timeout for databases
            log "Waiting for ${service} to be ready..."
            if ! kubectl wait --for=condition=Available deployment/${service} -n ${NAMESPACE} --timeout=600s; then
                warn "${service} deployment may not be fully ready, checking pod status..."
                kubectl get pods -n ${NAMESPACE} -l app=${service}
                kubectl describe pods -n ${NAMESPACE} -l app=${service}
            else
                log "${service} is ready!"
            fi
            
            # Additional wait for database services to be fully initialized
            if [ "$service" = "postgres" ]; then
                log "Waiting for PostgreSQL to be fully initialized..."
                sleep 30
            fi
        else
            warn "Deployment file not found for ${service}: ${deployment_file}"
        fi
    done
    
    log "Infrastructure services deployed successfully!"
}

deploy_application_services() {
    log "Deploying application services..."
    
    # Deploy application services in the correct order
    # Use the newer deployment files that follow the naming convention
    local app_services=("product" "counter" "barista" "kitchen" "proxy" "web")
    
    for service in "${app_services[@]}"; do
        # Check for both naming patterns and use the appropriate one
        local deployment_file=""
        if [ -f "${KUBERNETES_DIR}/deployments/${service}.yaml" ]; then
            deployment_file="${KUBERNETES_DIR}/deployments/${service}.yaml"
        elif [ -f "${KUBERNETES_DIR}/deployments/${service}-deployment.yaml" ]; then
            deployment_file="${KUBERNETES_DIR}/deployments/${service}-deployment.yaml"
        fi
        
        if [ -n "${deployment_file}" ]; then
            log "Deploying ${service} service..."
            kubectl apply -f "${deployment_file}"
            
            # Small delay between deployments to avoid resource conflicts
            sleep 10
        else
            warn "Deployment file not found for ${service} (checked both ${service}.yaml and ${service}-deployment.yaml)"
        fi
    done
    
    log "Waiting for application services to be ready..."
    for service in "${app_services[@]}"; do
        # Check which deployment name is actually used
        local deployment_name=""
        if kubectl get deployment ${service} -n ${NAMESPACE} &> /dev/null; then
            deployment_name=${service}
        elif kubectl get deployment ${service}-service -n ${NAMESPACE} &> /dev/null; then
            deployment_name=${service}-service
        fi
        
        if [ -n "${deployment_name}" ]; then
            log "Waiting for ${deployment_name} to be available..."
            if ! kubectl wait --for=condition=Available deployment/${deployment_name} -n ${NAMESPACE} --timeout=300s; then
                warn "${deployment_name} deployment may not be fully ready, checking status..."
                kubectl get pods -n ${NAMESPACE} -l app=${service}
                kubectl describe pods -n ${NAMESPACE} -l app=${service} | tail -20
            else
                log "${deployment_name} is ready!"
            fi
        fi
    done
    
    log "Application services deployed successfully!"
}

deploy_services() {
    log "Deploying Kubernetes services..."
    
    if [ -d "${KUBERNETES_DIR}/services" ]; then
        kubectl apply -f "${KUBERNETES_DIR}/services/"
        log "Services deployed successfully!"
    else
        warn "Services directory not found, skipping services deployment..."
    fi
}

deploy_ingress() {
    log "Deploying ingress resources..."
    
    # Create service account for AWS Load Balancer Controller
    if ! kubectl get serviceaccount aws-load-balancer-controller -n kube-system &> /dev/null; then
        log "Creating service account for AWS Load Balancer Controller..."
        kubectl create serviceaccount aws-load-balancer-controller -n kube-system
    fi
    
    # Deploy AWS Load Balancer Controller if not exists
    if ! kubectl get deployment aws-load-balancer-controller -n kube-system &> /dev/null; then
        log "AWS Load Balancer Controller not found, deploying..."
        
        if command_exists helm; then
            helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
            helm repo update
            
            local cluster_name=$(kubectl config current-context | cut -d'/' -f2)
            
            # If that doesn't work, try to get it from cluster info
            if [ -z "${cluster_name}" ] || [ "${cluster_name}" = "" ]; then
                cluster_name=$(kubectl cluster-info | grep -o 'https://[^.]*\.eks\.[^.]*\.amazonaws\.com' | cut -d'/' -f3 | cut -d'.' -f1)
            fi
            
            if [ -n "${cluster_name}" ]; then
                log "Installing AWS Load Balancer Controller for cluster: ${cluster_name}"
                helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
                    -n kube-system \
                    --set clusterName=${cluster_name} \
                    --set serviceAccount.create=false \
                    --set serviceAccount.name=aws-load-balancer-controller \
                    --wait --timeout=300s
            else
                warn "Could not determine cluster name, using default"
                helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
                    -n kube-system \
                    --set serviceAccount.create=false \
                    --set serviceAccount.name=aws-load-balancer-controller \
                    --wait --timeout=300s
            fi
        else
            warn "Helm not found, please install AWS Load Balancer Controller manually"
        fi
    fi
    
    if [ -f "${KUBERNETES_DIR}/ingress.yaml" ]; then
        log "Deploying ingress configuration..."
        kubectl apply -f "${KUBERNETES_DIR}/ingress.yaml"
        
        log "Waiting for ingress to be ready..."
        sleep 30
        
        log "Ingress deployed successfully!"
    else
        warn "Ingress file not found: ${KUBERNETES_DIR}/ingress.yaml"
    fi
}

deploy_hpa() {
    log "Deploying Horizontal Pod Autoscaler..."
    
    if [ -f "${KUBERNETES_DIR}/hpa.yaml" ]; then
        kubectl apply -f "${KUBERNETES_DIR}/hpa.yaml"
        log "HPA deployed successfully!"
    else
        warn "HPA file not found: ${KUBERNETES_DIR}/hpa.yaml"
    fi
}

deploy_monitoring() {
    if [ ! -d "${MONITORING_DIR}" ]; then
        warn "Monitoring directory not found, skipping monitoring deployment..."
        return 0
    fi
    
    log "Deploying monitoring stack..."
    
    if [ -d "${MONITORING_DIR}/prometheus" ]; then
        log "Deploying Prometheus..."
        kubectl apply -f "${MONITORING_DIR}/prometheus/"
        
        if kubectl get deployment prometheus -n ${MONITORING_NAMESPACE} &> /dev/null; then
            kubectl wait --for=condition=Available deployment/prometheus -n ${MONITORING_NAMESPACE} --timeout=300s
        fi
    else
        warn "Prometheus manifests not found, skipping..."
    fi
    
    if [ -d "${MONITORING_DIR}/grafana" ]; then
        log "Deploying Grafana..."
        kubectl apply -f "${MONITORING_DIR}/grafana/"
        
        if kubectl get deployment grafana -n ${MONITORING_NAMESPACE} &> /dev/null; then
            kubectl wait --for=condition=Available deployment/grafana -n ${MONITORING_NAMESPACE} --timeout=300s
        fi
    else
        warn "Grafana manifests not found, skipping..."
    fi
    
    log "Monitoring stack deployed successfully!"
}

verify_deployment() {
    log "Verifying deployment..."
    
    info ""
    info "=== Pod Status in ${NAMESPACE} ==="
    kubectl get pods -n ${NAMESPACE} -o wide
    
    info ""
    info "=== Pod Status in ${MONITORING_NAMESPACE} ==="
    kubectl get pods -n ${MONITORING_NAMESPACE} -o wide
    
    info ""
    info "=== Services in ${NAMESPACE} ==="
    kubectl get services -n ${NAMESPACE}
    
    info ""
    info "=== Ingress Status ==="
    kubectl get ingress -n ${NAMESPACE}
    
    info ""
    info "=== HPA Status ==="
    kubectl get hpa -n ${NAMESPACE} 2>/dev/null || warn "No HPA found"
    
    # Check for any failed pods
    info ""
    info "=== Failed Pods Check ==="
    local failed_pods=$(kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    local pending_pods=$(kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    
    if [ "$failed_pods" -gt 0 ]; then
        warn "Found $failed_pods failed pods"
        kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Failed
    fi
    
    if [ "$pending_pods" -gt 0 ]; then
        warn "Found $pending_pods pending pods"
        kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Pending
    fi
    
    # Get LoadBalancer endpoint
    info ""
    info "=== LoadBalancer Information ==="
    local lb_endpoint=$(kubectl get ingress coffeeshop-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "${lb_endpoint}" ] && [ "${lb_endpoint}" != "null" ]; then
        info "🎉 Application is available at: http://${lb_endpoint}"
        info "📊 Grafana dashboard: http://${lb_endpoint}/grafana (admin/admin)"
        info "🐰 RabbitMQ management: http://${lb_endpoint}/rabbitmq (admin/password)"
    else
        warn "LoadBalancer endpoint not ready yet. Check again in a few minutes with:"
        warn "kubectl get ingress coffeeshop-ingress -n ${NAMESPACE}"
    fi
    
    info ""
    info "=== Health Check Summary ==="
    local total_pods=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    info "Total pods: $total_pods"
    info "Running pods: $ready_pods"
    
    if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        info "✅ All pods are running successfully!"
    else
        warn "⚠️  Some pods may not be ready yet. Check individual pod logs if needed."
    fi
    
    info ""
    info "=== Useful Commands ==="
    info "View logs: kubectl logs -f deployment/<service-name> -n ${NAMESPACE}"
    info "Get pods: kubectl get pods -n ${NAMESPACE}"
    info "Describe pod: kubectl describe pod <pod-name> -n ${NAMESPACE}"
    info "Port forward: kubectl port-forward svc/<service-name> <local-port>:<remote-port> -n ${NAMESPACE}"
    info "Check events: kubectl get events -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp"
    
    log "Deployment verification completed!"
}

show_cleanup_info() {
    info ""
    info "=== Cleanup Commands ==="
    info "Remove application: kubectl delete namespace ${NAMESPACE}"
    info "Remove monitoring: kubectl delete namespace ${MONITORING_NAMESPACE}"
    info "Remove all: kubectl delete namespace ${NAMESPACE} ${MONITORING_NAMESPACE}"
    info ""
}

cleanup_deployment() {
    if [ "$1" = "cleanup" ]; then
        log "Cleaning up CoffeeShop deployment..."
        
        kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
        kubectl delete namespace ${MONITORING_NAMESPACE} --ignore-not-found=true
        
        log "Cleanup completed!"
        exit 0
    fi
}

usage() {
    local script_name=$(basename "$0")
    
    echo "Usage: $script_name [COMMAND]"
    echo ""
    echo "CoffeeShop Kubernetes Deployment"
    echo ""
    echo "Commands:"
    echo "  deploy        Deploy the complete application (default)"
    echo "  cleanup       Remove all deployed resources"
    echo "  help          Show this help message"
    echo ""
    echo "Prerequisites:"
    echo "  - kubectl installed and configured for EKS"
    echo "  - AWS CLI installed and configured"
    echo "  - Helm installed (for AWS Load Balancer Controller)"
    echo "  - EKS cluster already created"
    echo ""
    echo "Examples:"
    echo "  $script_name                    # Deploy application"
    echo "  $script_name deploy             # Deploy application"
    echo "  $script_name cleanup            # Clean up deployment"
    echo ""
}

main() {
    case "${1:-deploy}" in
        "deploy")
            log "Starting CoffeeShop Kubernetes deployment..."
            
            check_prerequisites
            create_namespaces
            deploy_secrets_and_configs
            deploy_storage
            deploy_infrastructure_services
            deploy_application_services
            deploy_services
            deploy_ingress
            deploy_hpa
            deploy_monitoring
            verify_deployment
            show_cleanup_info
            
            log "CoffeeShop application deployed successfully to Kubernetes!"
            ;;
        "cleanup")
            cleanup_deployment $1
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	targetNodeLabel = "node.restriction/target"
)

var (
	runtimeScheme = runtime.NewScheme()
	codecs        = serializer.NewCodecFactory(runtimeScheme)
	deserializer  = codecs.UniversalDeserializer()
)

type WebhookServer struct {
	server *http.Server
	client *kubernetes.Clientset
}

type patchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

func (whsvr *WebhookServer) getTargetNodeForNamespace(namespace string) (string, error) {
	ns, err := whsvr.client.CoreV1().Namespaces().Get(context.Background(), namespace, metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to get namespace %s: %v", namespace, err)
	}

	targetNode, exists := ns.Labels[targetNodeLabel]
	if !exists {
		log.Printf("Namespace %s does not have target node label %s, skipping pod mutation", namespace, targetNodeLabel)
		return "", nil
	}

	return targetNode, nil
}

func (whsvr *WebhookServer) mutate(ar *admissionv1.AdmissionReview) *admissionv1.AdmissionResponse {
	req := ar.Request
	var pod corev1.Pod

	if err := json.Unmarshal(req.Object.Raw, &pod); err != nil {
		log.Printf("Could not unmarshal raw object: %v", err)
		return &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	// Check if pod already has node selectors
	if len(pod.Spec.NodeSelector) > 0 {
		log.Printf("Pod %s in namespace %s already has node selectors, skipping mutation", pod.Name, pod.Namespace)
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	// Get target node from namespace label
	targetNode, err := whsvr.getTargetNodeForNamespace(pod.Namespace)
	if err != nil {
		log.Printf("Failed to get target node: %v", err)
		return &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	// If no target node is specified, allow the pod without modification
	if targetNode == "" {
		log.Printf("No target node specified for namespace %s, allowing pod without modification", pod.Namespace)
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	// Create patch to set node selector
	patch := []patchOperation{
		{
			Op:   "add",
			Path: "/spec/nodeSelector",
			Value: map[string]string{
				"kubernetes.io/hostname": targetNode,
			},
		},
	}

	patchBytes, err := json.Marshal(patch)
	if err != nil {
		return &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	return &admissionv1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *admissionv1.PatchType {
			pt := admissionv1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

func (whsvr *WebhookServer) serve(w http.ResponseWriter, r *http.Request) {
	var body []byte
	if r.Body != nil {
		if data, err := ioutil.ReadAll(r.Body); err == nil {
			body = data
		}
	}

	// verify the content type is accurate
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		log.Printf("contentType=%s, expect application/json", contentType)
		http.Error(w, "invalid Content-Type, expect `application/json`", http.StatusUnsupportedMediaType)
		return
	}

	var admissionResponse *admissionv1.AdmissionResponse
	ar := admissionv1.AdmissionReview{}
	if _, _, err := deserializer.Decode(body, nil, &ar); err != nil {
		log.Printf("Can't decode body: %v", err)
		admissionResponse = &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else {
		admissionResponse = whsvr.mutate(&ar)
	}

	admissionReview := admissionv1.AdmissionReview{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "admission.k8s.io/v1",
			Kind:       "AdmissionReview",
		},
	}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
	}

	resp, err := json.Marshal(admissionReview)
	if err != nil {
		log.Printf("Can't encode response: %v", err)
		http.Error(w, fmt.Sprintf("could not encode response: %v", err), http.StatusInternalServerError)
	}
	log.Printf("Ready to write response ...")
	if _, err := w.Write(resp); err != nil {
		log.Printf("Can't write response: %v", err)
		http.Error(w, fmt.Sprintf("could not write response: %v", err), http.StatusInternalServerError)
	}
}

func main() {
	var certFile string
	var keyFile string
	var port int

	certFile = "/etc/webhook/certs/tls.crt"
	keyFile = "/etc/webhook/certs/tls.key"
	port = 8443

	pair, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Printf("Failed to load key pair: %v", err)
	}

	// Create the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Printf("Failed to get in-cluster config: %v", err)
		os.Exit(1)
	}

	// Create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Printf("Failed to create clientset: %v", err)
		os.Exit(1)
	}

	whsvr := &WebhookServer{
		server: &http.Server{
			Addr:      fmt.Sprintf(":%v", port),
			TLSConfig: &tls.Config{Certificates: []tls.Certificate{pair}},
		},
		client: clientset,
	}

	// define http server and server handler
	mux := http.NewServeMux()
	mux.HandleFunc("/mutate", whsvr.serve)
	whsvr.server.Handler = mux

	// start webhook server in new routine
	go func() {
		if err := whsvr.server.ListenAndServeTLS("", ""); err != nil {
			log.Printf("Failed to listen and serve webhook server: %v", err)
		}
	}()

	// listening OS shutdown signal
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	log.Printf("Got OS shutdown signal, shutting down webhook server gracefully...")
	whsvr.server.Shutdown(context.Background())
}

package handlers

import (
	"encoding/json"
	"net/http"
)

type MessageResponse struct {
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func HelloHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := MessageResponse{
		Message: "Hello from API Server",
		Data: map[string]string{
			"version": "1.0.0",
		},
	}

	json.NewEncoder(w).Encode(response)
}

func GetItemsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	items := []map[string]any{
		{"id": 1, "name": "Item 1", "description": "Description for item 1"},
		{"id": 2, "name": "Item 2", "description": "Description for item 2"},
		{"id": 3, "name": "Item 3", "description": "Description for item 3"},
	}

	response := MessageResponse{
		Message: "Items retrieved successfully",
		Data:    items,
	}

	json.NewEncoder(w).Encode(response)
}

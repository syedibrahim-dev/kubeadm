package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// Item represents a document in MongoDB
type Item struct {
	ID          primitive.ObjectID `bson:"_id,omitempty"       json:"id"`
	Name        string             `bson:"name"                json:"name"`
	Description string             `bson:"description"         json:"description,omitempty"`
	CreatedAt   time.Time          `bson:"createdAt"           json:"createdAt"`
}

var col *mongo.Collection

// ─── Helpers ────────────────────────────────────────────────────────────────

func respond(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// cors wraps a handler with CORS headers (required when React dev server runs
// on a different port than the Go service)
func cors(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next(w, r)
	}
}

// ─── Handlers ───────────────────────────────────────────────────────────────

// GET /api/health
func healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbStatus := "connected"
	if err := col.Database().Client().Ping(ctx, nil); err != nil {
		dbStatus = "disconnected"
	}
	respond(w, http.StatusOK, map[string]string{
		"status":    "healthy",
		"version":   "1.1.0",
		"database":  dbStatus,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
}

// GET /api/items  →  list all items (newest first)
// POST /api/items →  create item  { name, description }
func itemsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		cursor, err := col.Find(ctx, bson.M{},
			options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}))
		if err != nil {
			respond(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		defer cursor.Close(ctx)

		var list []Item
		if err := cursor.All(ctx, &list); err != nil {
			respond(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		if list == nil {
			list = []Item{}
		}
		respond(w, http.StatusOK, map[string]any{"count": len(list), "items": list})

	case http.MethodPost:
		var item Item
		if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
			respond(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
		if strings.TrimSpace(item.Name) == "" {
			respond(w, http.StatusBadRequest, map[string]string{"error": "name is required"})
			return
		}
		item.ID = primitive.NewObjectID()
		item.CreatedAt = time.Now().UTC()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if _, err := col.InsertOne(ctx, item); err != nil {
			respond(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		respond(w, http.StatusCreated, item)

	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// DELETE /api/items/{id}
func deleteItemHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := strings.TrimPrefix(r.URL.Path, "/api/items/")
	if id == "" {
		respond(w, http.StatusBadRequest, map[string]string{"error": "id is required"})
		return
	}

	objID, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		respond(w, http.StatusBadRequest, map[string]string{"error": "invalid id format"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	result, err := col.DeleteOne(ctx, bson.M{"_id": objID})
	if err != nil {
		respond(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if result.DeletedCount == 0 {
		respond(w, http.StatusNotFound, map[string]string{"error": "item not found"})
		return
	}
	respond(w, http.StatusOK, map[string]string{"message": "deleted"})
}

// ─── Main ───────────────────────────────────────────────────────────────────

func main() {
	mongoURL := os.Getenv("MONGO_URL")
	if mongoURL == "" {
		mongoURL = "mongodb://mongodb:27017"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Connect to MongoDB
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURL))
	if err != nil {
		log.Fatal("MongoDB connect error:", err)
	}
	defer client.Disconnect(context.Background())

	if err := client.Ping(ctx, nil); err != nil {
		log.Fatal("MongoDB ping error:", err)
	}
	log.Println("✅ Connected to MongoDB")

	col = client.Database("itemsdb").Collection("items")

	// Routes
	// NOTE: In Go's ServeMux, "/api/items/" (with trailing slash) is a subtree
	// pattern that matches /api/items/123 etc. "/api/items" (no slash) is exact.
	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", cors(healthHandler))
	mux.HandleFunc("/api/items/", cors(deleteItemHandler)) // handles /api/items/{id}
	mux.HandleFunc("/api/items", cors(itemsHandler))       // handles /api/items exactly

	log.Printf("🚀 Go backend listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

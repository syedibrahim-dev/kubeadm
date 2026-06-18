# Stage 1 — BUILDER  (~800MB)
FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod ./

RUN GONOSUMDB="*" GOFLAGS="-mod=mod" go mod tidy

COPY main.go .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GONOSUMDB="*" GOFLAGS="-mod=mod" \
    go build -ldflags="-w -s" -o server .

    
FROM gcr.io/distroless/static-debian12 AS production

WORKDIR /app

# Copy ONLY the compiled binary from the builder stage
COPY --from=builder /app/server .

EXPOSE 8080

# distroless doesn't have a shell, so ENTRYPOINT must be exec-form (JSON array)
ENTRYPOINT ["/app/server"]

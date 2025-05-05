FROM golang:1.21 as builder
WORKDIR /workspace
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -a -o webhook-server .

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
WORKDIR /
COPY --from=builder /workspace/webhook-server .
ENTRYPOINT ["/webhook-server"] 
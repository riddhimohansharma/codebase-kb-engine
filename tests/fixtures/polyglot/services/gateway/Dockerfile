FROM golang:1.22 AS build
WORKDIR /src
COPY . .
RUN go build -o /out/gateway .
FROM gcr.io/distroless/base
COPY --from=build /out/gateway /gateway
ENTRYPOINT ["/gateway"]

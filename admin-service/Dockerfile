FROM ballerina/ballerina:2201.12.7 as builder
WORKDIR /app
COPY . .
RUN bal build
FROM ballerina/ballerina:2201.12.7 as runtime
WORKDIR /app
COPY --from=builder /app/target/bin/admin_service ./admin_service
EXPOSE 9006
ENV MONGO_URL=mongodb://wytee:cookingdsa@mongodb:27017/?authSource=admin \
    KAFKA_URL=kafka:9092 \
    SERVICE_PORT=9006
CMD ["bal", "run", "admin_service"]
FROM ballerina/ballerina:2201.12.10 as builder
USER root
WORKDIR /app
COPY . .
RUN bal build
FROM ballerina/ballerina:2201.12.10 as runtime
USER ballerina
WORKDIR /app
COPY --from=builder /app/target/bin/admin_service.jar ./admin_service.jar
EXPOSE 9006
CMD ["bal", "run", "admin_service.jar"]
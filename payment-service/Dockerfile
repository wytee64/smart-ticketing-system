FROM ballerina/ballerina:2201.12.10

WORKDIR /app

COPY . .

USER root
RUN bal build
USER ballerina
EXPOSE 8084
CMD ["bal", "run", "target/bin/payment_service.jar"]

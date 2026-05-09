FROM ballerina/ballerina:2201.12.10

WORKDIR /app

COPY . /app

USER root
RUN bal build
USER ballerina
EXPOSE 9003
CMD ["bal", "run", "target/bin/ticketing_service.jar"]

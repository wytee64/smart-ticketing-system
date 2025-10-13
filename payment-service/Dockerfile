FROM ballerina/ballerina:2201.8.0

WORKDIR /app

COPY Ballerina.toml .
COPY service.bal .

RUN bal build --skip-tests

EXPOSE 8084

CMD ["bal", "run", "--offline", "/app"]

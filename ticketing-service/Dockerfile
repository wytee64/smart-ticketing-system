FROM ballerina/ballerina:2201.12.7

WORKDIR /app

COPY . /app

RUN bal build --skip-tests

EXPOSE 9003

CMD ["bal", "run"]

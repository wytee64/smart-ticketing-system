FROM --platform=$BUILDPLATFORM ballerina/ballerina:2201.12.10

WORKDIR /app
COPY Ballerina.toml .
COPY main.bal .

# Build the project (no tests are run by 'bal build' anyway)
RUN bal build

EXPOSE 9010
CMD ["bal", "run"]
# Build stage
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

# Copy pom.xml first for better caching
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline -B

# Copy source code
COPY src/ ./src/

# Build the JAR and copy dependencies to a lib folder
RUN mvn clean package -DskipTests -B && \
    mvn dependency:copy-dependencies -DincludeScope=runtime -DoutputDirectory=target/jars && \
    cp target/debezium-connector-ocel-*.jar target/jars/

# Output stage - copy all JARs to output
FROM scratch AS export

COPY --from=builder /app/target/jars/ /

FROM registry.access.redhat.com/ubi8/openjdk-8

COPY target/*.jar /opt/app.jar

CMD java -jar /opt/app.jar

EXPOSE 8080
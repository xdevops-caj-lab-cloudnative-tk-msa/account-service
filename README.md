# 微服务容器化改造

## 改造前的微服务

- [account-service](https://github.com/xdevops-caj-lab-cloudnative-tk/PiggyMetrics/tree/master/account-service)

## 每个微服务有自己的代码仓库

将原来微服务属于一个Maven module改为每个微服务有自己的代码仓库。

添加`.gitignore`文件，以忽略一些不需要提交到代码仓库的文件。

在pom.xml中将parent直接改为spring-boot-starter-parent，并引入spring-cloud-dependencies。

```xml
	<parent>
		<groupId>org.springframework.boot</groupId>
		<artifactId>spring-boot-starter-parent</artifactId>
		<version>2.0.3.RELEASE</version>
		<relativePath/> <!-- lookup parent from repository -->
	</parent>

	<properties>
		<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
		<spring-cloud.version>Finchley.RELEASE</spring-cloud.version>
		<java.version>1.8</java.version>
	</properties>

	<dependencyManagement>
		<dependencies>
			<dependency>
				<groupId>org.springframework.cloud</groupId>
				<artifactId>spring-cloud-dependencies</artifactId>
				<version>${spring-cloud.version}</version>
				<type>pom</type>
				<scope>import</scope>
			</dependency>
		</dependencies>
	</dependencyManagement>
```

指定groupId:

```xml
<groupId>com.piggymetrics</groupId>
```

## 本地构建运行

```bash
mvn clean install && mvn spring-boot:run
```

此时发现报错，因为程序试图从Spring Cloud Config Server拉取应用配置。

## 去除从Spring Cloud Config Server拉取配置

将`src/main/resources`下的bootstrap.yml改为application.yaml。

并移除其中`spring.cloud.config`的内容。

同时在pom.xml文件中去除对应的依赖：
```xml
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-config</artifactId>
        </dependency>
```

再次本地构建运行。

发现程序可以启动成功，但是报错无法注册到Eureka Server。

## 去除注册到Eureka Server

修改Spring Boot应用类AccountApplication.java，将`@EnableDiscoveryClient`注解去掉，并去掉对应的`import`语句。

同时在pom.xml文件中去除对应的依赖：
```xml
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
        </dependency>
```
或
```xml
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-eureka</artifactId>
        </dependency>
```

再次本地构建运行。

发现程序可以启动成功，但是报错无法连接到数据库（本例子数据库为MongoDB）。

在解决连接到MongoDB数据库问题之前，先检查一下剩余的Spring Cloud依赖。

## 剩余的Spring Cloud依赖

本服务使用了以下Spring Cloud依赖：
- spring-cloud-starter-oauth2
- spring-cloud-starter-openfeign
- spring-cloud-starter-sleuth
- spring-cloud-starter-bus-amqp
- spring-cloud-starter-netflix-hystrix
- spring-cloud-netflix-hystrix-stream

如果程序不再依赖任何Sprng Cloud组建，则可以去除全部Spring Cloud依赖，并再次本地构建运行。

## 在本地运行MongoDB

参见[mongodb](https://github.com/xdevops-caj-lab-cloudnative-tk-msa/mongodb) 来创建MongoDB数据库`accountdb`。

## 应用配置

将Spring Cloud Config Server中account-service的配置文件放到application.yml中：

```yaml
security:
  oauth2:
    client:
      clientId: account-service
      clientSecret: ${ACCOUNT_SERVICE_PASSWORD}
      accessTokenUri: http://auth-service:5000/uaa/oauth/token
      grant-type: client_credentials
      scope: server

spring:
  data:
    mongodb:
      host: account-mongodb
      username: user
      password: ${MONGODB_PASSWORD}
      database: piggymetrics
      port: 27017

server:
  servlet:
    context-path: /accounts
  port: 6000

feign:
  hystrix:
    enabled: true
```

修改上述配置如下：

```yaml
spring:
  application:
    name: account-service
  data:
    mongodb:
      uri: ${MONGODB_URI:mongodb://user:password@localhost:27017/accountdb}

security:
  oauth2:
    client:
      clientId: account-service
      clientSecret: ${ACCOUNT_SERVICE_PASSWORD}
      accessTokenUri: http://auth-service:8080/uaa/oauth/token
      grant-type: client_credentials
      scope: server

server:
  servlet:
    context-path: /accounts

feign:
  hystrix:
    enabled: true
```

说明：
- `spring.application.name`指定了应用名称
- `spring.data.mongodb.uri`指定了MongoDB数据库连接字符串，如果没有指定，则使用默认值`mongodb://user:password@localhost:27017/accountdb`。
- `security.oauth2.client.accessTokenUri`指定了OAuth2认证服务的地址，将auth-service的端口改为默认端口8080
- 使用默认端口（8080）

再次本地构建运行，发现报错Missing tokenInfoUri and userInfoUri and there is no JWT verifier key。

## 连接认证服务

在application.yml中补充`user-info-uri`。

补充后的配置：

```yaml
security:
  oauth2:
    client:
      clientId: account-service
      clientSecret: ${ACCOUNT_SERVICE_PASSWORD}
      accessTokenUri: http://auth-service:8080/uaa/oauth/token
      grant-type: client_credentials
      scope: server
    resource:
      user-info-uri: http://auth-service:8080/uaa/users/current
```

说明：
- ACCOUNT_SERVICE_PASSWORD的值直接从环境变量中获取

再次本地构建运行。

发现程序可以启动成功，但是这时配置认证服务连接还是有问题的：
- `http://auth-service:8080`其实在本地是访问不通的

## 本地调试运行

添加一个application-local.yaml文件，用于本地调试。

```yaml
server:
  port: 6000

security:
  oauth2:
    client:
      accessTokenUri: http://localhost:5000/uaa/oauth/token
    resource:
      user-info-uri: http://localhost:5000/uaa/users/current
```

说明：
- `accessTokenUri`和`user-info-uri`指定了本地的认证服务地址
- `server.port`指定了本地运行的端口

本地调试运行：
```bash
mvn spring-boot:run -Dspring.profiles.active=local
```

## 让OpenFeign client不使用Ribbon

在gateway转发请求给account-service后，当account-service再调用auth-service时，报错：
Load balancer does not have available server for client: auth-service

这是因为account-service使用OpenFeign client去调用auth-service，而OpenFeign client默认使用Ribbon做负载均衡，而Ribbon默认使用Eureka做服务发现。
因此需要指定OpenFeign client url，从而不使用Ribbon，也不需要依赖Eureka。

AuthServiceClient.java代码片段：
```java
@FeignClient(name = "auth-service", url = "${auth-service.url}")
public interface AuthServiceClient {
    // ...
}
```

StatisticsServiceClient.java代码片段：
```java
@FeignClient(name = "statistics-service", fallback = StatisticsServiceClientFallback.class, url = "${statistics-service.url}")
public interface StatisticsServiceClient {
    // ...
}
```

在application.yml中配置OpenFeign client url。

代码片段：

```yaml
auth-service:
  url: http://auth-service:8080

statistics-service:
  url: http://statistics-service:8080
```

类似的，在application-local.yml中配置本地调试的OpenFeign client url。

代码片段：

```yaml
auth-service:
  url: http://localhost:5000

statistics-service:
  url: http://localhost:7000
```


再次本地调试运行。

## 构建容器镜像

创建Dockerfile文件：

```bash
FROM registry.access.redhat.com/ubi8/openjdk-8

COPY target/*.jar /opt/app.jar

CMD java -jar /opt/app.jar

EXPOSE 8080
```

构建容器镜像：

```bash
podman build -t account-service .
```

推送容器镜像到镜像仓库：

```bash
podman login quay.io
# replace as your repository
podman tag account-service:latest quay.io/xxx/account-service:latest
podman push quay.io/xxx/account-service:latest
```

## 部署到Kubernetes

在piggymeticrs-config仓库中集中管理多个微服务的Kubernetes YAML。

### 部署MongoDB

TODO 使用Helm部署bitnami/mongodb

### 部署应用

TODO Kubernetes deployment, confimap, secret, service


## Troubleshooting

### 后台不断报RabbitMQ连接错误或报队列已满的错误

去除spring-cloud-starter-bus-amqp和spring-cloud-netflix-hystrix-stream依赖。

因为部署到Kubernetes时，一般会采用Prometheus+Grafana来监控应用，因此不需要Hystrix Stream。

```xml
		<dependency>
			<groupId>org.springframework.cloud</groupId>
			<artifactId>spring-cloud-starter-bus-amqp</artifactId>
		</dependency>
		<dependency>
			<groupId>org.springframework.cloud</groupId>
			<artifactId>spring-cloud-netflix-hystrix-stream</artifactId>
		</dependency>
```







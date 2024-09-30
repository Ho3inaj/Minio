# MinIO Distributed Setup with Docker Swarm

This guide explains how to set up a distributed MinIO deployment using Docker Swarm.

## Prerequisites
- Docker installed on all nodes
- Docker Swarm initialized (`docker swarm init` on manager node)
- Swarm nodes added (`docker swarm join` on worker nodes)

## Steps

### 1. Label the Nodes
You need to label the nodes in your Swarm cluster to ensure each MinIO instance is deployed to a specific node. For this example, we are using the labels `minio-1`, `minio-2`, `minio-3`, and `minio-4`.

Run the following commands on the Swarm manager node:

```bash
docker node update --label-add role=minio-1 <node-1-name>
docker node update --label-add role=minio-2 <node-2-name>
docker node update --label-add role=minio-3 <node-3-name>
docker node update --label-add role=minio-4 <node-4-name>
```
### Since the docker-compose.yml file uses external volumes for data persistence, you need to manually create these volumes on each Swarm node before deploying the stack.
```bash
docker volume create --name=minio1-data
docker volume create --name=minio2-data
docker volume create --name=minio3-data
docker volume create --name=minio4-data
```
### deploy stack 
``` bash
docker stack deploy -c docker-compose.yml minio_distributed
```
###Accessing the miniO console
Once the stack is deployed, you can access the MinIO console through any node in the Docker Swarm cluster due to Docker Swarm's service mesh
- MinIO-1 Console: `http://<node-1-ip>:9010` or `http://<node-2-ip>:9010`
- MinIO-2 Console: `http://<node-2-ip>:9012` or `http://<node-1-ip>:9012`
- MinIO-3 Console: `http://<node-3-ip>:9013` or `http://<node-1-ip>:9013`
- MinIO-4 Console: `http://<node-4-ip>:9014` or `http://<node-1-ip>:9014`

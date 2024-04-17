terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.1"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

resource "null_resource" "update-kubeconfig" {
  depends_on = [aws_eks_addon.ebs-csi]


  provisioner "local-exec" {
    command = "aws eks --region ap-northeast-2 update-kubeconfig --name simon-test"
  }
}

resource "aws_ebs_volume" "jenkins" {
  availability_zone = "ap-northeast-2a"
  size              = 10
  tags = {
    Name = "jenkins-volume"
  }
}

resource "aws_ebs_volume" "argo" {
  availability_zone = "ap-northeast-2c"
  size              = 30
  tags = {
    Name = "volume-argo"
  }
}

output "ebs_volume_id" {
  value = aws_ebs_volume.jenkins.id
}

resource "null_resource" "create_jenkins_namespace" {
  depends_on = [null_resource.update-kubeconfig]

  provisioner "local-exec" {
    command = "kubectl create ns jenkins"
  }
}

resource "local_file" "ebs_volume_jenkins_yaml" {
  depends_on = [null_resource.create_jenkins_namespace]

  content  = <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ap-northeast-2a
  awsElasticBlockStore:
    volumeID: "${aws_ebs_volume.jenkins.id}"
    fsType: ext4
EOF

  filename = "${path.module}/ebs-volume-jenkins.yaml"
}

resource "null_resource" "apply_kubernetes_manifest" {
  depends_on = [null_resource.create_jenkins_namespace, local_file.ebs_volume_jenkins_yaml]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ebs-volume-jenkins.yaml -n jenkins"
  }
}

resource "local_file" "ebs_volume_yaml-jenkins_pvc" {
  depends_on = [null_resource.create_jenkins_namespace]

  content  = <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

  filename = "${path.module}/ebs-volume_pvc-jenkins.yaml"
}

resource "null_resource" "apply_kubernetes_manifest_pvc" {
  depends_on = [null_resource.create_jenkins_namespace, local_file.ebs_volume_yaml-jenkins_pvc]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ebs-volume_pvc-jenkins.yaml -n jenkins"
  }
}




module "jenkins" {
  depends_on = [null_resource.create_jenkins_namespace]
  source  = "terraform-module/release/helm"
  version = "2.6.0"

  namespace  = "jenkins"
  repository = "https://charts.jenkins.io"

  app = {
    name          = "jenkins"
    version       = "5.1.5"
    chart         = "jenkins"
    force_update  = true
    wait          = false
    recreate_pods = false
    deploy        = 1
  }
  values = [templatefile("jenkins-values.yaml", {
    region                = var.main-region
    storage               = "10Gi"
    pvc_name              = var.jenkins_pvc
  })]

  set = [
    {
      name  = "labels.kubernetes\\.io/name"
      value = "jenkins"
    },
    {
      name  = "service.labels.kubernetes\\.io/name"
      value = "jenkins"
    },
  ]

  set_sensitive = [
    {
      path  = "controller.admin.username"
      value = "jenkins"
    },

  ]


}




resource "local_file" "ingress-jenkins_yaml" {
  depends_on = [null_resource.create_jenkins_namespace, module.jenkins]

  content  = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-alb
  namespace: jenkins
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-2:553186839963:certificate/a63aa8dd-b019-4ca6-b69c-1dce6e139bce
    alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
spec:
  ingressClassName: alb
  rules:
  - host: jen.seunghobet.link
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ssl-redirect
            port:
              name: use-annotation
      - path: /jenkins
        pathType: Prefix
        backend:
          service:
            name: jenkins
            port:
              number: 8080
EOF

  filename = "${path.module}/ingress-jenkins_yaml"
}

resource "null_resource" "apply_kubernetes_manifest_ingress" {
  depends_on = [null_resource.create_jenkins_namespace, local_file.ingress-jenkins_yaml]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ingress-jenkins_yaml -n jenkins"
  }
}


resource "null_resource" "create_argo_namespace" {
  depends_on = [null_resource.update-kubeconfig]


  provisioner "local-exec" {
    command = "kubectl create ns argocd"
  }
}

resource "local_file" "ebs_volume_argo_yaml" {
  depends_on = [null_resource.create_argo_namespace]

  content  = <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: argo-pv
spec:
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - ap-northeast-2c
  awsElasticBlockStore:
    volumeID: "${aws_ebs_volume.argo.id}"
    fsType: ext4
EOF

  filename = "${path.module}/ebs-volume-argo.yaml"
}

resource "null_resource" "apply_kubernetes_manifest_argo_pv" {
  depends_on = [null_resource.create_argo_namespace, local_file.ebs_volume_argo_yaml]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ebs-volume-argo.yaml -n argocd"
  }
}

resource "local_file" "ebs_volume_yaml_argo_pvc" {
  depends_on = [null_resource.create_argo_namespace]

  content  = <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: argo-pvc
  namespace: argocd
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
EOF

  filename = "${path.module}/ebs-volume-argo_pvc.yaml"
}

resource "null_resource" "apply_kubernetes_manifest_argo_pvc" {
  depends_on = [null_resource.create_argo_namespace, local_file.ebs_volume_yaml_argo_pvc]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ebs-volume-argo_pvc.yaml -n argocd"
  }
}


module "argo" {
  depends_on = [null_resource.create_argo_namespace]
  source  = "terraform-module/release/helm"
  version = "2.6.0"

  namespace  = "argocd"
  repository =  "https://argoproj.github.io/argo-helm"


  app = {
    name          = "argocd"
    version       = "6.7.12"
    chart         = "argo-cd"
    force_update  = true
    wait          = false
    recreate_pods = false
    deploy        = 1
  }
values = [templatefile("argo.yml", {
    region                = var.main-region
    storage               = "30Gi"
    pvc_name              = var.argo-pvc
  })]

  set = [
    {
      name  = "labels.kubernetes\\.io/name"
      value = "argo"
    },
    {
      name  = "service.labels.kubernetes\\.io/name"
      value = "argo"
    },
  ]

  set_sensitive = [
    {
      path  = "master.adminUser"
      value = "admin"
    },
  ]
}



resource "local_file" "ingress-argo_yaml" {
  depends_on = [null_resource.create_argo_namespace, module.argo]

  content  = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-2:553186839963:certificate/cc24040b-b31d-4674-bf59-c5564908cc6a
    alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
spec:
  rules:
  - host: argo.seunghobet.link
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ssl-redirect
            port:
              name: use-annotation
      - path: /argocd
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              name: http

EOF

  filename = "${path.module}/ingress-argo_yaml"
}

resource "null_resource" "apply_kubernetes_manifest_ingress-argo" {
  depends_on = [null_resource.create_argo_namespace, module.argo, local_file.ingress-argo_yaml]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/ingress-argo_yaml -n argocd"
  }
}





resource "null_resource" "patch_argo_basehref" {
  depends_on = [null_resource.create_argo_namespace, null_resource.apply_kubernetes_manifest_ingress-argo]
  provisioner "local-exec" {
    command = "kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{\"data\":{\"server.basehref\":\"/argocd\"}}'"
  }
}

resource "null_resource" "patch_argo_insecure" {
  depends_on = [null_resource.create_argo_namespace, null_resource.patch_argo_basehref]
  provisioner "local-exec" {
    command = "kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{\"data\":{\"server.insecure\":\"true\"}}'"
  }
}

resource "null_resource" "patch_argo_rootpath" {
  depends_on = [null_resource.create_argo_namespace, null_resource.patch_argo_insecure]
  provisioner "local-exec" {
    command = "kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{\"data\":{\"server.rootpath\":\"/argocd\"}}'"
  }
}


resource "null_resource" "restart_argo_deployments" {
  depends_on = [null_resource.create_argo_namespace,null_resource.patch_argo_rootpath]
  provisioner "local-exec" {
    command = "kubectl rollout restart deployments --namespace argocd"


  }
}

resource "null_resource" "patch_argo_accounts" {
  depends_on = [null_resource.create_argo_namespace, null_resource.restart_argo_deployments]
  provisioner "local-exec" {
    command = "kubectl patch configmap argocd-cm -n argocd --type merge -p '{\"data\":{\"accounts.argo\":\"apiKey\"}}'"

  }
}






resource "local_file" "argocd-rbac" {
  depends_on = [null_resource.create_argo_namespace, local_file.ingress-argo_yaml, null_resource.patch_argo_accounts]
  filename = "${path.module}/argocd-rbac.yml"
  content = <<-EOT

apiVersion: v1
data:
  policy.csv: |
    g, argo, role:admin
  policy.default: role:''
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd




EOT
}

resource "null_resource" "apply_argocd_rbac" {
  depends_on = [local_file.argocd-rbac]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/argocd-rbac.yml"


  }
}


resource "null_resource" "install_docker" {
  depends_on = [null_resource.apply_argocd_rbac]
  provisioner "local-exec" {
    command = <<-EOT
      # Docker 설치
      sudo yum -y install docker

      # Docker 서비스 시작
      sudo service docker start

      # 현재 사용자를 docker 그룹에 추가
      sudo usermod -aG docker $(whoami)

      # AWS ECR에 로그인
      aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 553186839963.dkr.ecr.ap-northeast-2.amazonaws.com
    EOT
  }
}

resource "null_resource" "create_kpop_namespace" {
  provisioner "local-exec" {
    command = "kubectl create ns kpop"
  }
  depends_on = [null_resource.install_docker]
}

resource "null_resource" "create_ecr_secret_kpop" {
  provisioner "local-exec" {
    command = <<-EOT
      # 스크립트 파일을 만듭니다.
      echo "#!/bin/bash" > create_ecr_secret_kpop.sh
      echo "ecr_token=\$(aws ecr get-login-password --region ap-northeast-2)" >> create_ecr_secret_kpop.sh
      echo "kubectl create secret docker-registry ecr-registry-secret \\" >> create_ecr_secret_kpop.sh
      echo "  --docker-server=553186839963.dkr.ecr.ap-northeast-2.amazonaws.com \\" >> create_ecr_secret_kpop.sh
      echo "  --docker-username=AWS \\" >> create_ecr_secret_kpop.sh
      echo "  --docker-password=\$ecr_token \\" >> create_ecr_secret_kpop.sh
      echo "  -n kpop" >> create_ecr_secret_kpop.sh

      # 스크립트 파일을 실행합니다.
      chmod +x create_ecr_secret_kpop.sh
      ./create_ecr_secret_kpop.sh
    EOT
  }
  depends_on = [null_resource.create_kpop_namespace]
}

resource "null_resource" "create_ecr_secret_jenkins" {
  provisioner "local-exec" {
    command = <<-EOT
      # 스크립트 파일을 만듭니다.
      echo "#!/bin/bash" > create_ecr_secret_jenkins.sh
      echo "ecr_token=\$(aws ecr get-login-password --region ap-northeast-2)" >> create_ecr_secret_jenkins.sh
      echo "kubectl create secret docker-registry ecr-registry-secret \\" >> create_ecr_secret_jenkins.sh
      echo "  --docker-server=553186839963.dkr.ecr.ap-northeast-2.amazonaws.com \\" >> create_ecr_secret_jenkins.sh
      echo "  --docker-username=AWS \\" >> create_ecr_secret_jenkins.sh
      echo "  --docker-password=\$ecr_token \\" >> create_ecr_secret_jenkins.sh
      echo "  -n jenkins" >> create_ecr_secret_jenkins.sh

      # 스크립트 파일을 실행합니다.
      chmod +x create_ecr_secret_jenkins.sh
      ./create_ecr_secret_jenkins.sh
    EOT
  }
  depends_on = [null_resource.create_kpop_namespace]
}


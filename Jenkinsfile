pipeline {
  agent { label 'jenkins' }

  environment {
    REGISTRY_CRED   = credentials('docker-hub')
    IMAGE_REGISTRY  = "hoangvu42"
    SONARQUBE_ENV   = "sonarqube-server"
    GITOPS_REPO_URL = "https://github.com/v4224/dacn-gitops.git"
    ALL_SERVICES    = "api-gateway,identity-service,profile-service,notification-service,post-service,file-service"
  }

  options {
    skipDefaultCheckout(true)
    timestamps()
  }

  stages {
    stage('Checkout Source') {
      steps {
        checkout scm
        script {
          env.BRANCH = env.BRANCH_NAME
          env.IS_TAG = env.TAG_NAME != null
          echo "Building for ${env.IS_TAG.toBoolean() ? 'tag' : 'branch'}: ${env.IS_TAG.toBoolean() ? env.TAG_NAME : env.BRANCH}"
        }
      }
    }
  }
}

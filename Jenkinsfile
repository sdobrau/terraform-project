pipeline {
    parameters {
        string(name: 'TERRAFORM_VERSION',
               defaultValue: '1.15.0-rc2',
               description: "Terraform version to download")
    }
    environment {
        TF_AWS_EXPERIMENT_dynamodb_global_secondary_index = "1"
        AWS_ACCESS_KEY_ID = credentials("AWS_ACCESS_KEY_ID")
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION = "us-east-1"
    }
    agent {
        docker {
            image 'sdobrau/terraform-ci:2026_19_04'
            label 'worker-docker'
            registryUrl 'https://ghcr.io'
            registryCredentialsId 'ghcr_credentials'
            alwaysPull true
        }
    }
    options {
        timeout(time:5, unit: 'MINUTES')
    }
    stages {
        stage('Notify') {
            steps {
                // Notify a start of build; appends the extra message at the end (note: prefix with separators if needed)
                ircNotify notifyOnStart:true, extraMessage: "Running build ${env.JOB_NAME}... at ${env.BUILD_URL}"
            }
        }
        stage('BetterLeaks') {
            steps {
                sh 'betterleaks git -v .'
            }
        }
        stage('ClamAV') {
            steps {
                sh 'clamscan --recursive .'
            }
        }
        stage('TerraformInit') {
            steps {
                sh 'terraform init'
            }
        }
        stage ('TerraformValidate') {
            steps {
                sh 'terraform validate'
            }
        }
        stage('TerraformPlan') {
            steps {
                sh 'terraform plan'
            }
        }
        stage('TfLint') {
            steps {
                sh 'tflint --init' // expect .tflint.tcl
                // across builds
                sh 'tflint --recursive'
            }
        }
        // TODO: setup
        // stage('Checkov') {
        //     steps {
        //         sh 'checkov --quiet --skip-resources-without-violations -d .'
        //     }
        // }y
        stage('TrivyConfig') {
            steps {
                sh 'trivy config --report summary . --ignorefile .trivyignore'
            }
        }
        stage('OPA') {
            steps {
                // TODO
                sh 'echo "doing opa"'
            }
        }
        stage('Terratest') {
            steps {
                sh "go mod init ${env.GIT_URL}"
                sh 'go mod tidy'
                sh 'cd tests'
                sh 'go test -v -timeout 10m'
            }
        }
        stage('Deploy') {
            when {
                expression {
                    currentBuild.result == null || currentBuild.result == 'SUCCESS'
                }
            }
            steps {
                sh 'terraform apply'
            }
        }
    }
    // post {
    //     always {
    //         ircNotify targets: "sdobrau #jenkins-room", customMessage:
    //         "${env.JOB_NAME} run"
    //     }
    //     success {
    //         ircNotify targets: "sdobrau #jenkins-room", customMessage:
    //         "${env.JOB_NAME} successfully built"
    //     }
    //     failure {
    //         ircNotify targets: "sdobrau #jenkins-room", customMessage:
    //         "${env.JOB_NAME} successfully built"
    //         ircNotify targets: "sdobrau #jenkins-room", customMessage:
    //         "${env.JOB_NAME} failed to build"
    //     }
    // }
}

pipeline {
  agent any
  stages {
    stage('error') {
      steps {
        powershell 'NutanixAutomation.ps1'
      }
    }

  }
  parameters {
    string(defaultValue: '', description: 'The user who will be using the VM', name: 'Owner', trim: false)
    choice(choices: ['Standard', 'Developer'], description: '', name: 'VM_Type')
  }
}
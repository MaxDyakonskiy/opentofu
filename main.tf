# 1. https://library.tf/
# 2. https://life.astralinux.ru/pages/viewpage.action?pageId=150957186
# 3. https://gist.github.com/kvaps/db5548d208a0817337e95f5884c507e8
# 4. https://forum.opennebula.io/t/terraform-is-missing-vm-creation-attributes-cpu-model-model-host-passthrough/11136
# 5. https://github.com/OpenNebula/terraform-provider-opennebula/issues/26

# У этой переменной есть default-значение, которое и будет использоваться
variable "brest_endpoint" {
  type    = string
  default = "https://opennebula.test.lan:8443/RPC2"
}

# Для этой переменной при вызове OpenTofu загружается файл ~/opentofu-termidesk/brestLogin.tfvars
variable "brest_username" {
  type = string
}

variable "brest_password" {
  type = string
}

terraform {
  required_providers {
    opennebula = {
      source = "OpenNebula/opennebula"

      version = "~> 1.4"
    }
  }
}

provider "opennebula" {
  endpoint = var.brest_endpoint
  username = var.brest_username
  password = var.brest_password
  insecure = false
}

# Генерируем SSH-ключи для подключения к стенду
resource "terraform_data" "gen-ssh-keys" {
  count = fileexists("~/.ssh/termidesk_rsa.pub") ? 0 : 1
  provisioner "local-exec" {
    command = "ssh-keygen -t rsa -C termidesk-deploy -f ~/.ssh/termidesk_rsa -q -P ''"
  }
}

# Создаём шаблон

# Синтаксис через EOF, как это показано по ссылке №3 в начале файла,
# больше не работает. Теперь используются 'tags', 'raw',
# 'user_inputs ' и 'template_section'.
# 1. 'tags': одна пара ключ/значение, помещаются в начало шаблона
# 2. 'raw': в существующих ВМ на Бресте нигде нет, можно не указывать.
# 3. 'user_inputs': не знаю сценарии, где применяются, в нашем случае не нужно.
# 4. 'template_section': используется вместо EOF, чтобы задать любые параметры,
# недоступные в качестве аргументов для ресурсов.
# См. подробнее https://github.com/OpenNebula/terraform-provider-opennebula/issues/26
resource "opennebula_template" "t-tm-alse" {
  count = 2

  cpu                   = 2
  memory                = 8096
  name                  = (count.index == 0) ? "t-alse-1-7-2-4-11" : "t-alse-1-7-2-5-16"
  sched_ds_requirements = "NAME=ceph_vm_ssd"
  vcpu                  = 4

  # Тестируем, как отработает переменная 'USERNAME'
  context = {
    NETWORK        = "YES"
    SETHOSTNAME    = "$NAME"
    ETH0_VLAN_ID   = "333"
    ETH0_DNS       = "10.177.128.198 10.177.180.248"
    ETH0_GATEWAY   = "10.177.202.254"
    ETH0_MASK      = "255.255.255.0"
    USERNAME       = "adminlocal"
    SSH_PUBLIC_KEY = file("~/.ssh/termidesk_rsa.pub")
  }

  # Используем non-persistent базовый образ
  disk {
    image_id   = (count.index == 0) ? "13126" : "13105"
    dev_prefix = "vd"
  }

  # Не можем указать 'video' в блоке 'graphics'
  template_section {
    name = "graphics"
    elements = {
      type   = "SPICE"
      listen = "0.0.0.0"
      video  = "qxl"
    }
  }

  # Не можем указать 'ssh' и 'rdp' в блоке 'nic'
  # Используем подсеть 897, которую нам выделили
  template_section {
    name = "nic"
    elements = {
      network_id = "897"
      model      = "virtio"
      ssh        = "yes"
      rdp        = "yes"
    }
  }

  # Не можем указать 'machine' в блоке 'os'
  template_section {
    name = "os"
    elements = {
      arch    = "x86_64"
      boot    = "disk0"
      machine = "q35"
    }
  }

  template_section {
    name = "cpu_model"
    elements = {
      model = "host-passthrough"
    }
  }
}

resource "opennebula_virtual_machine" "vm-tm-alse" {
  # https://www.reddit.com/r/Terraform/comments/oyyja9/accessing_indices_in_a_data_source/
  for_each = tomap({
    vm1  = "vm-bf"   # Brest Front
    vm2  = "vm-bn"   # Brest Node
    vm3  = "vm-ald"  # ALDPro
    vm4  = "vm-rmq"  # RabbitMQ
    vm5  = "vm-tm-1" # Task Manager-1
    vm6  = "vm-tm-2" # Task Manager-2
    vm7  = "vm-gw-1" # Gateway-1
    vm8  = "vm-gw-2" # Gateway-2
    vm9  = "vm-lb"   # Load Balancer
    vm10 = "vm-ra"   # Remote Assistant
    vm11 = "vm-pa"   # Portal of Administrator
    vm12 = "vm-br-1" # Broker-1
    vm13 = "vm-br-2" # Broker-2
  })

  template_id = (each.key == "vm1" || each.key == "vm2" || each.key == "vm3") ? opennebula_template.t-tm-alse[0].id : opennebula_template.t-tm-alse[1].id
  name        = each.value
  tags = {
    AUTOSTARTVM   = "1"
    HYPERVISOR    = "kvm"
    SERVICEUSERVM = "1"
    LABELS        = "Termidesk"
  }
}

# Загружаем образ, который ранее создал Packer
#resource "opennebula_image" "i-tm-alse-1-7-5-16" {
#  name = "i-tm-alse"
#  description = "Base image for Termidesk nodes"
#  datastore_id = "102"
#  persistent = false
#  type = "OS"
#  dev_prefix = "vd"
#  format = "qcow2"
#  path = "../packer/images-from-packer/i-tm-alse-1_7_5_16"
#}

#output "i-tm-alse-1-7-5-16-id" {
#  value = "opennebula_image.i-tm-alse-1-7-5-16.id"
#  description = "Сохраняем ID загруженного образа, чтобы затем добавить к шаблону"
#}

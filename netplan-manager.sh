#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# === Глобальные переменные ===
LOG_FILE="/var/log/netplan-manager.log"  # Файл журнала действий
CONFIG_DIR="/etc/netplan"                # Путь к директории с конфигами
EDITOR="nano"                            # Редактор по умолчанию
TEMPLATE_DIR="/etc/netplan/netplan-template" # Путь к директории с шаблонами


# === Функция логирования действий ===
log_action() {
    local timestamp
    timestamp=$(date "+%F %T")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}
# === Получение списка конфигурационных файлов Netplan ===
use_template() {
    echo "===== ДОСТУПНЫЕ ШАБЛОНЫ ====="
    mapfile -t templates < <(find "$TEMPLATE_DIR" -maxdepth 1 -type f -name "*.yaml" -exec basename {} \;)
    if [ ${#templates[@]} -eq 0 ]; then
        echo "Нет доступных шаблонов в $TEMPLATE_DIR"
        read -rp "Нажмите Enter для возврата..." dummy
        return
    fi

    for i in "${!templates[@]}"; do
        echo "$((i+1))) ${templates[$i]}"
    done

    read -rp "Выберите номер шаблона или 0 для отмены: " sel
    [[ "$sel" == "0" || "$sel" == "q" ]] && return

    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#templates[@]} )); then
        selected="${templates[$((sel-1))]}"
        template_path="$TEMPLATE_DIR/$selected"

        # Имя нового файла: tmp-<номер>-<название шаблона>.off
        fname="tmp-${sel}-${selected%.yaml}.off"
        final_path="$CONFIG_DIR/$fname"

        cp "$template_path" "$final_path"
        chmod 600 "$final_path"
        log_action "Создан временный шаблон: $final_path"

        echo "Открытие шаблона в редакторе для адаптации..."
        $EDITOR "$final_path"

        echo
        echo "Файл сохранён как: $final_path"
        echo "Чтобы применить — переименуйте его в .yaml и выполните 'netplan apply'"
        read -rp "Нажмите Enter для возврата..." dummy
    else
        echo "Неверный выбор"
        sleep 1
    fi
}
# === Функция: конструктор конфигов ===
# netplan_constructor() {
#     echo "=============================="
#     echo "     КОНСТРУКТОР КОНФИГОВ"
#     echo "=============================="

#     read -rp "Введите имя интерфейса (например, eth0, vlan10, br0, wg0): " iface
#     [[ -z "$iface" || "$iface" == "q" || "$iface" == "0" ]] && return

#     echo "Выберите тип конфигурации:"
#     echo "1) DHCP"
#     echo "2) Статический IP"
#     echo "3) Wi-Fi (WPA2/WPA3)"
#     echo "4) VLAN"
#     echo "5) Bridge"
#     echo "6) DMZ (VLAN или Bridge)"
#     echo "7) VPN-интерфейс (wg0/tun0)"
#     echo "8) VRF (Virtual Routing)"
#     echo "9) VXLAN туннель"
#     echo "10) Open vSwitch (OVS)"
#     echo "11) SR-IOV"
#     echo "12) Виртуальные Ethernet-интерфейсы"
#     echo "13) Модем (LTE/3G)"
#     echo "0) Назад"
#     read -rp "> " type
#     [[ "$type" == "0" || "$type" == "q" ]] && return

#     config="network:\n  version: 2\n  renderer: networkd"

#     case $type in
#         1)
#             config+="\n  ethernets:\n    $iface:\n      dhcp4: true"
#             ;;
#         2)
#             read -rp "IP-адрес (CIDR): " ip
#             [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             read -rp "Шлюз: " gw
#             [[ "$gw" == "q" || "$gw" == "0" ]] && return
#             read -rp "DNS (через запятую): " dns
#             [[ "$dns" == "q" || "$dns" == "0" ]] && return
#             config+="\n  ethernets:\n    $iface:\n      dhcp4: false\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             ;;
#         3)
#             read -rp "SSID: " ssid
#             [[ "$ssid" == "q" || "$ssid" == "0" ]] && return
#             read -rp "Пароль или EAP: " pass
#             [[ "$pass" == "q" || "$pass" == "0" ]] && return
#             config+="\n  wifis:\n    $iface:\n      access-points:\n        \"$ssid\":\n          password: \"$pass\"\n      dhcp4: true"
#             ;;
#         4)
#             read -rp "ID VLAN: " vlan_id
#             read -rp "Физический интерфейс: " link
#             read -rp "IP-адрес (CIDR): " ip
#             read -rp "Шлюз: " gw
#             read -rp "DNS (через запятую): " dns
#             config+="\n  ethernets:\n    $link: {}\n  vlans:\n    $iface:\n      id: $vlan_id\n      link: $link\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             ;;
#         5)
#             mapfile -t physifs < <(get_interfaces)
#             if [ ${#physifs[@]} -eq 0 ]; then echo "Нет интерфейсов"; return; fi
#             echo "Выберите интерфейсы для моста (через запятую):"
#             for i in "${!physifs[@]}"; do echo "$((i+1))) ${physifs[$i]}"; done
#             read -rp "> " ifsel; [[ "$ifsel" == "q" || "$ifsel" == "0" ]] && return
#             bridge_ifaces=(); IFS=',' read -ra nums <<< "$ifsel"
#             for n in "${nums[@]}"; do
#                 [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#physifs[@]} )) && bridge_ifaces+=("${physifs[$((n-1))]}")
#             done
#             [[ ${#bridge_ifaces[@]} -eq 0 ]] && echo "Не выбрано" && return
#             bridge_iflist=$(IFS=,; echo "${bridge_ifaces[*]}")
#             read -rp "IP-адрес (оставьте пустым для DHCP): " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             config+="\n  bridges:\n    $iface:\n      interfaces: [${bridge_iflist// /, }]"
#             if [[ -z "$ip" ]]; then
#                 config+="\n      dhcp4: true"
#             else
#                 read -rp "Шлюз: " gw; [[ "$gw" == "q" || "$gw" == "0" ]] && return
#                 read -rp "DNS (через запятую): " dns; [[ "$dns" == "q" || "$dns" == "0" ]] && return
#                 config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             fi
#             ;;
#         6)
#             # DMZ (VLAN или Bridge)
#             echo "Выберите базу DMZ:"
#             echo "1) VLAN"
#             echo "2) Bridge"
#             read -rp "> " dmz_mode
#             [[ "$dmz_mode" == "q" || "$dmz_mode" == "0" ]] && return

#             if [[ $dmz_mode == 1 ]]; then
#                 # DMZ на базе VLAN: выбор физического интерфейса из списка
#                 read -rp "ID VLAN: " vlan_id
#                 [[ "$vlan_id" == "q" || "$vlan_id" == "0" ]] && return

#                 mapfile -t physifs < <(get_interfaces)
#                 if [ ${#physifs[@]} -eq 0 ]; then
#                     echo "Нет интерфейсов"
#                     return
#                 fi
#                 echo "Выберите физический интерфейс для DMZ (номер):"
#                 for i in "${!physifs[@]}"; do
#                     echo "$((i+1))) ${physifs[$i]}"
#                 done
#                 read -rp "> " sel
#                 [[ "$sel" == "q" || "$sel" == "0" ]] && return
#                 if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#physifs[@]} )); then
#                     echo "Неверный выбор"
#                     return
#                 fi
#                 link=${physifs[$((sel-1))]}

#                 read -rp "IP-адрес: " ip
#                 [[ "$ip" == "q" || "$ip" == "0" ]] && return
#                 read -rp "Шлюз: " gw
#                 [[ "$gw" == "q" || "$gw" == "0" ]] && return
#                 read -rp "DNS (через запятую): " dns
#                 [[ "$dns" == "q" || "$dns" == "0" ]] && return

#                 config+="\n  ethernets:\n    $link: {}\
#                             \n  vlans:\n    $iface:\n      id: $vlan_id\
#                             \n      link: $link\
#                             \n      addresses: [$ip]\
#                             \n      routes:\n        - to: default\n          via: $gw\
#                             \n      nameservers:\n        addresses: [${dns//,/ }]"
#             elif [[ $dmz_mode == 2 ]]; then
#                 …
#             elif [[ $dmz_mode == 2 ]]; then
#                 # DMZ на базе Bridge
#                 mapfile -t physifs < <(get_interfaces)
#                 if [ ${#physifs[@]} -eq 0 ]; then
#                     echo "Нет интерфейсов"
#                     return
#                 fi
#                 echo "Выберите интерфейсы для DMZ-моста (через запятую):"
#                 for i in "${!physifs[@]}"; do
#                     echo "$((i+1))) ${physifs[$i]}"
#                 done
#                 read -rp "> " sel
#                 [[ "$sel" == "q" || "$sel" == "0" ]] && return

#                 dmz_ifaces=()
#                 IFS=',' read -ra nums <<< "$sel"
#                 for n in "${nums[@]}"; do
#                     if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#physifs[@]} )); then
#                         dmz_ifaces+=("${physifs[$((n-1))]}")
#                     fi
#                 done
#                 [[ ${#dmz_ifaces[@]} -eq 0 ]] && echo "Не выбрано" && return
#                 dmz_iflist=$(IFS=,; echo "${dmz_ifaces[*]}")

#                 # Ввод сетевых параметров
#                 read -rp "IP-адрес: " ip
#                 [[ "$ip" == "q" || "$ip" == "0" ]] && return
#                 read -rp "Шлюз: " gw
#                 [[ "$gw" == "q" || "$gw" == "0" ]] && return
#                 read -rp "DNS (через запятую): " dns
#                 [[ "$dns" == "q" || "$dns" == "0" ]] && return

#                 # Построение блока DMZ-моста с правильными отступами
#                 config+="\n  bridges:\n    $iface:\n      wakeonlan: true\n      interfaces: [${dmz_iflist// /, }]\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             else
#                 echo "Неверный выбор"
#                 return
#             fi
#             ;;
#         7)
#             echo "Выберите тип VPN-интерфейса:"
#             echo "1) WireGuard (wg0)"
#             echo "2) OpenVPN (tun0)"
#             read -rp "> " vpn_mode
#             [[ "$vpn_mode" == "q" || "$vpn_mode" == "0" ]] && return

#             if [[ "$vpn_mode" == "1" ]]; then
#                 read -rp "PrivateKey (файл /etc/wireguard/private.key): " pkey
#                 [[ "$pkey" == "q" || "$pkey" == "0" ]] && return
#                 read -rp "Peer PublicKey: " peerkey
#                 read -rp "Endpoint (IP:port): " endpoint
#                 read -rp "Allowed IPs (через запятую): " allowed

#                 config+="\n  tunnels:\n    $iface:\n      mode: wireguard\n      addresses: [10.0.0.2/24]\n      key: $(cat $pkey)\n      peers:\n        - key: $peerkey\n          endpoint: $endpoint\n          allowed-ips: [${allowed//,/ }]"

#             elif [[ "$vpn_mode" == "2" ]]; then
#                 echo "Выберите режим OpenVPN подключения:"
#                 echo "1) DHCP (выдаётся VPN-сервером)"
#                 echo "2) Статический IP внутри VPN-сети"
#                 read -rp "> " open_mode
#                 [[ "$open_mode" == "q" || "$open_mode" == "0" ]] && return

#                 config+="\n  ethernets:\n    $iface:"
#                 if [[ "$open_mode" == "1" ]]; then
#                     config+="\n      dhcp4: true"
#                 elif [[ "$open_mode" == "2" ]]; then
#                     read -rp "IP-адрес: " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
#                     read -rp "Шлюз (внутри VPN): " gw
#                     read -rp "DNS-серверы: " dns
#                     config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#                 else
#                     echo "Неверный выбор"
#                     return
#                 fi
#             else
#                 echo "Неверный выбор"
#                 return
#             fi
#             ;;
#         8)
#             read -rp "Имя VRF: " vrfname
#             [[ "$vrfname" == "q" || "$vrfname" == "0" ]] && return
#             read -rp "ID таблицы маршрутизации (table ID): " tableid
#             [[ "$tableid" == "q" || "$tableid" == "0" ]] && return
#             read -rp "Сетевой интерфейс для VRF: " physif
#             [[ "$physif" == "q" || "$physif" == "0" ]] && return
#             read -rp "IP-адрес для $physif: " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             read -rp "Шлюз: " gw; [[ "$gw" == "q" || "$gw" == "0" ]] && return
#             read -rp "DNS (через запятую): " dns; [[ "$dns" == "q" || "$dns" == "0" ]] && return

#             config+="\n  vrfs:\n    $vrfname:\n      table: $tableid"
#             config+="\n  ethernets:\n    $physif:\n      vrf: $vrfname\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             ;;

#         9)
#             read -rp "Имя интерфейса VXLAN (например, vxlan100): " vxname
#             [[ "$vxname" == "q" || "$vxname" == "0" ]] && return
#             read -rp "ID VXLAN: " vxid
#             read -rp "Интерфейс-носитель (обычно ethX): " parent
#             read -rp "Локальный IP (local): " localip
#             read -rp "Удалённый IP (remote): " remoteip
#             read -rp "Мультикаст группа (опц.): " mcast
#             read -rp "Порт (по умолчанию 4789): " port
#             port=${port:-4789}
#             read -rp "MTU (опц.): " mtu

#             config+="\n  tunnels:\n    $vxname:\n      mode: vxlan\n      id: $vxid\n      link: $parent\n      local: $localip\n      remote: $remoteip\n      port: $port"
#             [[ -n "$mcast" ]] && config+="\n      group: $mcast"
#             [[ -n "$mtu" ]] && config+="\n      mtu: $mtu"
#             ;;

#         10)
#             read -rp "Имя OVS bridge (например, ovs-br0): " ovsbr
#             [[ "$ovsbr" == "q" || "$ovsbr" == "0" ]] && return
#             mapfile -t ovsifs < <(get_interfaces)
#             if [ ${#ovsifs[@]} -eq 0 ]; then echo "Нет доступных интерфейсов"; return; fi
#             echo "Выберите интерфейсы для OVS bridge (через запятую):"
#             for i in "${!ovsifs[@]}"; do echo "$((i+1))) ${ovsifs[$i]}"; done
#             read -rp "> " sel
#             [[ "$sel" == "q" || "$sel" == "0" ]] && return
#             ovslist=(); IFS=',' read -ra nums <<< "$sel"
#             for n in "${nums[@]}"; do
#                 [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ovsifs[@]} )) && ovslist+=("${ovsifs[$((n-1))]}")
#             done
#             [[ ${#ovslist[@]} -eq 0 ]] && echo "Ничего не выбрано" && return
#             ovsjoined=$(IFS=,; echo "${ovslist[*]}")
#             read -rp "IP-адрес (CIDR): " ip
#             [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             read -rp "Шлюз: " gw
#             [[ "$gw" == "q" || "$gw" == "0" ]] && return
#             read -rp "DNS (через запятую): " dns
#             [[ "$dns" == "q" || "$dns" == "0" ]] && return

#             config+="\n  openvswitch:\n    bridges:\n      $ovsbr:\n        interfaces: [${ovsjoined// /, }]\n  ethernets:\n    $ovsbr:\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             ;;

#         11)
#             read -rp "Имя интерфейса SR-IOV (например, enp3s0f0): " sriov_if
#             [[ "$sriov_if" == "q" || "$sriov_if" == "0" ]] && return
#             read -rp "Количество виртуальных функций (VF): " vf_count
#             [[ "$vf_count" == "q" || "$vf_count" == "0" ]] && return
#             read -rp "IP-адрес (CIDR): " ip
#             [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             read -rp "Шлюз: " gw
#             [[ "$gw" == "q" || "$gw" == "0" ]] && return
#             read -rp "DNS-серверы: " dns
#             [[ "$dns" == "q" || "$dns" == "0" ]] && return

#             config+="\n  ethernets:\n    $sriov_if:\n      sriov: true\n      virtual-function-count: $vf_count\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             ;;

#         12)
#             read -rp "Имя veth-интерфейса (например, veth0): " veth1
#             [[ "$veth1" == "q" || "$veth1" == "0" ]] && return
#             read -rp "Имя пары veth-интерфейса (например, veth1): " veth2
#             [[ "$veth2" == "q" || "$veth2" == "0" ]] && return
#             read -rp "IP-адрес для $veth1 (CIDR): " ip
#             [[ "$ip" == "q" || "$ip" == "0" ]] && return
#             read -rp "Шлюз: " gw
#             [[ "$gw" == "q" || "$gw" == "0" ]] && return
#             read -rp "DNS-серверы: " dns
#             [[ "$dns" == "q" || "$dns" == "0" ]] && return

#             config+="\n  ethernets:\n    $veth1:\n      match:\n        name: $veth1\n      set-name: $veth1\n      peer: $veth2\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             config+="\n    $veth2:\n      match:\n        name: $veth2\n      set-name: $veth2"
#             ;;

#         13)
#             echo "Выберите тип модемного подключения:"
#             echo "1) DHCP (PPP/LTE выдаёт IP)"
#             echo "2) Статический IP через модем"
#             read -rp "> " mode
#             [[ "$mode" == "q" || "$mode" == "0" ]] && return

#             read -rp "Имя интерфейса модема (например, wwan0): " modem_if
#             [[ "$modem_if" == "q" || "$modem_if" == "0" ]] && return

#             config+="\n  ethernets:\n    $modem_if:"

#             if [[ "$mode" == "1" ]]; then
#                 config+="\n      dhcp4: true"
#             elif [[ "$mode" == "2" ]]; then
#                 read -rp "IP-адрес: " ip
#                 read -rp "Шлюз: " gw
#                 read -rp "DNS (через запятую): " dns
#                 config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
#             else
#                 echo "Неверный выбор"
#                 return
#             fi

#             read -rp "Указать APN (Access Point Name)? (y/n): " apn_ask
#             if [[ "$apn_ask" == "y" ]]; then
#                 read -rp "APN: " apn
#                 config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ access-point: $apn")
#             fi

#             read -rp "Указать PIN-код SIM? (y/n): " pin_ask
#             if [[ "$pin_ask" == "y" ]]; then
#                 read -rp "PIN-код: " pin
#                 config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ sim-pin: $pin")
#             fi
#             ;;



#     esac

#     read -rp "Добавить MAC-адрес? (y/n): " mac_yes
#     if [[ $mac_yes == y ]]; then
#         read -rp "MAC-адрес: " mac
#         config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ macaddress: $mac")
#     fi

#     read -rp "Добавить MTU? (y/n): " mtu_yes
#     if [[ $mtu_yes == y ]]; then
#         read -rp "MTU: " mtu
#         config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ mtu: $mtu")
#     fi

#     read -rp "Добавить Wake-on-LAN? (y/n): " wol_yes
#     if [[ $wol_yes == y ]]; then
#         config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ wakeonlan: true")
#     fi

#     echo -e "\nПредпросмотр конфигурации:\n=========================="
#     echo -e "$config"
#     echo "=========================="

#     read -rp "Имя файла (без .yaml): " fname
#     [[ "$fname" == "q" || "$fname" == "0" || -z "$fname" ]] && return

#     file="$CONFIG_DIR/${fname}.yaml"

#     read -rp "Сохранить и применить? (y/n): " confirm
#     [[ "$confirm" == "q" || "$confirm" == "0" ]] && return

#     if [[ $confirm == y ]]; then
#         echo -e "$config" > "$file"
#         sudo chmod 600 "$file"
#         log_action "Создан конфиг $file через конструктор"
#         netplan try --timeout 30 || echo "Ошибка применения. Проверьте вручную."
#     else
#         echo "Отменено."
#     fi
# }
netplan_constructor() {
    echo "=============================="
    echo "     КОНСТРУКТОР КОНФИГОВ"
    echo "=============================="

    read -rp "Введите имя интерфейса (например, eth0, vlan10, br0, wg0): " iface
    [[ -z "$iface" || "$iface" == "q" || "$iface" == "0" ]] && return

    echo "Выберите тип конфигурации:"
    echo "1) DHCP"
    echo "2) Статический IP"
    echo "3) Wi-Fi (WPA2/WPA3)"
    echo "4) VLAN"
    echo "5) Bridge"
    echo "6) DMZ (VLAN или Bridge)"
    echo "7) VPN-интерфейс (wg0/tun0)"
    echo "8) VRF (Virtual Routing)"
    echo "9) VXLAN туннель"
    echo "10) Open vSwitch (OVS)"
    echo "11) SR-IOV"
    echo "12) Виртуальные Ethernet-интерфейсы"
    echo "13) Модем (LTE/3G)"
    echo "0) Назад"
    read -rp "> " type
    [[ "$type" == "0" || "$type" == "q" ]] && return

    config="network:\n  version: 2\n  renderer: networkd"

    case $type in
        1)
            read -rp "Включить IPv6 (dhcp6: true)? (y/n): " ipv6
            read -rp "Сделать интерфейс optional (не блокирует загрузку)? (y/n): " opt

            config+="\n  ethernets:\n    $iface:\n      dhcp4: true"
            [[ "$ipv6" == "y" ]] && config+="\n      dhcp6: true"
            [[ "$opt" == "y" ]]  && config+="\n      optional: true"
            ;;
        2)
            ip=$(ask_ip "IP-адрес (CIDR)") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  ethernets:\n    $iface:\n      dhcp4: false\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            ;;
        3)
            echo "Режим Wi-Fi:"
            echo "1) WPA2/WPA3 Personal"
            echo "2) WPA2-Enterprise (EAP)"
            read -rp "> " wmode
            [[ "$wmode" == "q" || "$wmode" == "0" ]] && return

            read -rp "SSID (название Wi-Fi сети): " ssid
            [[ -z "$ssid" || "$ssid" == "q" || "$ssid" == "0" ]] && return

            if [[ "$wmode" == "1" ]]; then
                while true; do
                    read -rp "Пароль (8+ символов): " pass
                    [[ "$pass" == "q" || "$pass" == "0" ]] && return
                    if (( ${#pass} >= 8 )); then break; else echo "❌ Слишком короткий пароль"; fi
                done

                config+="\n  wifis:\n    $iface:\n      access-points:\n        \"$ssid\":\n          password: \"$pass\"\n      dhcp4: true"

            elif [[ "$wmode" == "2" ]]; then
                read -rp "EAP-тип (например, peap): " eap
                read -rp "Имя пользователя (identity): " identity
                read -rp "Пароль: " eap_pass

                config+="\n  wifis:\n    $iface:\n      access-points:\n        \"$ssid\": {}\n      dhcp4: true\n      auth:\n        key-management: wpa-eap\n        eap:\n          - $eap\n        identity: \"$identity\"\n        password: \"$eap_pass\""
            else
                echo "❌ Неверный выбор"
                return
            fi
            ;;
        4)
            read -rp "ID VLAN: " vlan_id
            read -rp "Физический интерфейс: " link
            if ! ip link show "$link" >/dev/null 2>&1; then
                echo "❌ Интерфейс $link не найден"
                return
            fi

            ip=$(ask_ip "IP-адрес (CIDR)") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  ethernets:\n    $link: {}\n  vlans:\n    $iface:\n      id: $vlan_id\n      link: $link\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            ;;
        5)
            mapfile -t physifs < <(get_interfaces)
            if [ ${#physifs[@]} -eq 0 ]; then echo "Нет интерфейсов"; return; fi
            echo "Выберите интерфейсы для моста (через запятую):"
            for i in "${!physifs[@]}"; do echo "$((i+1))) ${physifs[$i]}"; done
            read -rp "> " ifsel; [[ "$ifsel" == "q" || "$ifsel" == "0" ]] && return
            bridge_ifaces=(); IFS=',' read -ra nums <<< "$ifsel"
            for n in "${nums[@]}"; do
                [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#physifs[@]} )) && bridge_ifaces+=("${physifs[$((n-1))]}")
            done
            [[ ${#bridge_ifaces[@]} -eq 0 ]] && echo "Не выбрано" && return
            bridge_iflist=$(IFS=,; echo "${bridge_ifaces[*]}")
            read -rp "IP-адрес (оставьте пустым для DHCP): " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
            config+="\n  bridges:\n    $iface:\n      interfaces: [${bridge_iflist// /, }]"
            if [[ -z "$ip" ]]; then
                config+="\n      dhcp4: true"
            else
                gw=$(ask_plain_ip "Шлюз") || return
                dns=$(ask_dns_list) || return
                config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            fi
            ;;
        6)
            echo "Выберите базу DMZ:"
            echo "1) VLAN"
            echo "2) Bridge"
            read -rp "> " dmz_mode
            [[ "$dmz_mode" == "q" || "$dmz_mode" == "0" ]] && return

            if [[ "$dmz_mode" == 1 ]]; then
                read -rp "ID VLAN: " vlan_id
                mapfile -t physifs < <(get_interfaces)
                if [ ${#physifs[@]} -eq 0 ]; then echo "Нет интерфейсов"; return; fi
                echo "Выберите физический интерфейс:"
                for i in "${!physifs[@]}"; do echo "$((i+1))) ${physifs[$i]}"; done
                read -rp "> " sel
                [[ "$sel" == "q" || "$sel" == "0" ]] && return
                link=${physifs[$((sel-1))]}

                ip=$(ask_ip "IP-адрес") || return
                gw=$(ask_plain_ip "Шлюз") || return
                dns=$(ask_dns_list) || return

                config+="\n  ethernets:\n    $link: {}\n  vlans:\n    $iface:\n      id: $vlan_id\n      link: $link\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            elif [[ "$dmz_mode" == 2 ]]; then
                # Аналогично case 5), но с другим текстом и переменной
                ...
            else
                echo "Неверный выбор"
                return
            fi
            ;;
        7)
            echo "Выберите тип VPN-интерфейса:"
            echo "1) WireGuard (wg0)"
            echo "2) OpenVPN (tun0)"
            read -rp "> " vpn_mode
            [[ "$vpn_mode" == "q" || "$vpn_mode" == "0" ]] && return

            if [[ "$vpn_mode" == "1" ]]; then
                read -rp "Сгенерировать ключи автоматически (нужен wg)? (y/n): " autogen
                if [[ "$autogen" == "y" && -x "$(command -v wg)" ]]; then
                    pkey=$(wg genkey)
                    peerkey=$(wg genkey | wg pubkey)
                    echo "Ваш приватный ключ: $pkey"
                    echo "Пример публичного ключа peer: $peerkey"
                else
                    read -rp "PrivateKey (файл): " pkey_file
                    [[ "$pkey_file" == "q" || "$pkey_file" == "0" ]] && return
                    pkey=$(cat "$pkey_file")
                    read -rp "Peer PublicKey: " peerkey
                fi

                read -rp "Endpoint (IP:port): " endpoint
                read -rp "Allowed IPs (через запятую): " allowed
                read -rp "Отключить таблицу маршрутизации (table: off)? (y/n): " taboff

                config+="\n  tunnels:\n    $iface:\n      mode: wireguard\n      addresses: [10.0.0.2/24]\n      key: $pkey\n      peers:\n        - key: $peerkey\n          endpoint: $endpoint\n          allowed-ips: [${allowed//,/ }]"
                [[ "$taboff" == "y" ]] && config+="\n      table: off"

            elif [[ "$vpn_mode" == "2" ]]; then
                echo "[!] Это настройка интерфейса tun0 после установления VPN"
                echo "1) DHCP"
                echo "2) Статический IP"
                read -rp "> " open_mode
                config+="\n  ethernets:\n    $iface:"
                if [[ "$open_mode" == "1" ]]; then
                    read -rp "Сделать optional? (y/n): " opt
                    config+="\n      dhcp4: true"
                    [[ "$opt" == "y" ]] && config+="\n      optional: true"
                elif [[ "$open_mode" == "2" ]]; then
                    ip=$(ask_ip "IP-адрес") || return
                    gw=$(ask_plain_ip "Шлюз") || return
                    dns=$(ask_dns_list) || return
                    config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
                fi
            fi
            ;;
        8)
            read -rp "Имя VRF: " vrfname
            read -rp "ID таблицы маршрутизации (table ID): " tableid
            read -rp "Сетевой интерфейс: " physif
            ip=$(ask_ip "IP-адрес") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  vrfs:\n    $vrfname:\n      table: $tableid"
            config+="\n  ethernets:\n    $physif:\n      vrf: $vrfname\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            ;;
        9)
            read -rp "Имя интерфейса VXLAN (например vxlan100): " vxname
            read -rp "ID VXLAN: " vxid
            read -rp "Интерфейс-носитель (обычно ethX): " parent
            read -rp "Локальный IP (local): " localip
            read -rp "Удалённый IP (remote): " remoteip
            ping -c1 "$remoteip" >/dev/null || echo "⚠️ Не удалось пинговать $remoteip"

            read -rp "Мультикаст группа (опц.): " mcast
            read -rp "Порт (по умолчанию 4789): " port; port=${port:-4789}
            read -rp "MTU (опц.): " mtu

            config+="\n  tunnels:\n    $vxname:\n      mode: vxlan\n      id: $vxid\n      link: $parent\n      local: $localip\n      remote: $remoteip\n      port: $port"
            [[ -n "$mcast" ]] && config+="\n      group: $mcast"
            [[ -n "$mtu" ]] && config+="\n      mtu: $mtu"
            ;;
        10)
            if ! command -v ovs-vsctl >/dev/null; then
                echo "❌ Open vSwitch не установлен. Установите пакет openvswitch-switch"
                return
            fi
            read -rp "Имя OVS bridge: " ovsbr
            mapfile -t ovsifs < <(get_interfaces)
            if [ ${#ovsifs[@]} -eq 0 ]; then echo "Нет интерфейсов"; return; fi
            echo "Выберите интерфейсы для моста (через запятую):"
            for i in "${!ovsifs[@]}"; do echo "$((i+1))) ${ovsifs[$i]}"; done
            read -rp "> " sel
            ovslist=(); IFS=',' read -ra nums <<< "$sel"
            for n in "${nums[@]}"; do
                [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ovsifs[@]} )) && ovslist+=("${ovsifs[$((n-1))]}")
            done
            ovsjoined=$(IFS=,; echo "${ovslist[*]}")
            ip=$(ask_ip "IP-адрес") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  openvswitch:\n    bridges:\n      $ovsbr:\n        interfaces: [${ovsjoined// /, }]\n  ethernets:\n    $ovsbr:\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            ;;
        11)
            read -rp "Интерфейс SR-IOV (например, enp3s0f0): " sriov_if
            if [[ ! -f "/sys/class/net/$sriov_if/device/sriov_totalvfs" ]]; then
                echo "❌ Устройство $sriov_if не поддерживает SR-IOV"
                return
            fi
            read -rp "Количество VF: " vf_count
            ip=$(ask_ip "IP-адрес") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  ethernets:\n    $sriov_if:\n      sriov: true\n      virtual-function-count: $vf_count\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            ;;
        12)
            echo "[!] veth используется для контейнеров или bridge-сетей"
            read -rp "Имя veth-интерфейса: " veth1
            read -rp "Имя пары: " veth2
            ip=$(ask_ip "IP-адрес для $veth1") || return
            gw=$(ask_plain_ip "Шлюз") || return
            dns=$(ask_dns_list) || return

            config+="\n  ethernets:\n    $veth1:\n      match:\n        name: $veth1\n      set-name: $veth1\n      peer: $veth2\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            config+="\n    $veth2:\n      match:\n        name: $veth2\n      set-name: $veth2"
            ;;
        13)
            echo "Тип подключения модема:"
            echo "1) DHCP"
            echo "2) Статический IP"
            read -rp "> " mode
            read -rp "Имя интерфейса модема (например wwan0): " modem_if
            if ! ip link show "$modem_if" >/dev/null 2>&1; then
                echo "❌ Интерфейс $modem_if не найден"
                return
            fi

            config+="\n  ethernets:\n    $modem_if:"
            if [[ "$mode" == "1" ]]; then
                config+="\n      dhcp4: true"
            elif [[ "$mode" == "2" ]]; then
                ip=$(ask_ip "IP-адрес") || return
                gw=$(ask_plain_ip "Шлюз") || return
                dns=$(ask_dns_list) || return
                config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns// / }]"
            fi

            read -rp "Указать APN (Access Point Name)? (y/n): " apn_ask
            [[ "$apn_ask" == "y" ]] && read -rp "APN: " apn && config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ access-point: $apn")

            read -rp "Указать PIN SIM? (y/n): " pin_ask
            [[ "$pin_ask" == "y" ]] && read -rp "PIN: " pin && config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ sim-pin: $pin")
            ;;
    esac
        read -rp "Добавить MAC-адрес? (y/n): " mac_yes
    if [[ "$mac_yes" == "y" ]]; then
        read -rp "Автоопределить MAC? (y/n): " auto_mac
        if [[ "$auto_mac" == "y" ]]; then
            mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null)
            [[ -z "$mac" ]] && echo "Не удалось получить MAC" && return
        else
            read -rp "Введите MAC: " mac
        fi
        config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ macaddress: $mac")
    fi

    read -rp "Добавить MTU? (y/n): " mtu_yes
    [[ "$mtu_yes" == "y" ]] && read -rp "MTU: " mtu && config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ mtu: $mtu")

    read -rp "Добавить Wake-on-LAN? (y/n): " wol_yes
    [[ "$wol_yes" == "y" ]] && config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ wakeonlan: true")
    echo -e "\nПредпросмотр конфигурации:\n=========================="
    echo -e "$config"
    echo "=========================="

    default_name="auto-${type}-${iface}.off"
    read -rp "Имя конфигурации (по умолчанию: $default_name): " fname
    fname="${fname:-$default_name}"
    file="$CONFIG_DIR/$fname"

    TMPDIR=$(mktemp -d)
    echo -e "$config" > "$TMPDIR/test.yaml"
    if netplan generate --debug --root "$TMPDIR" >/dev/null 2>&1; then
        echo "✅ Синтаксис OK"
    else
        echo "❌ Ошибка синтаксиса"
        rm -r "$TMPDIR"
        return
    fi
    rm -r "$TMPDIR"

    read -rp "Сохранить конфиг в $file? (y/n): " confirm
    [[ "$confirm" == "y" ]] && echo -e "$config" > "$file" && chmod 600 "$file" && log_action "Создан конфиг $file через конструктор" && echo "[+] Файл сохранён: $file"
}
# === Получение списка файлов конфигурации Netplan ===
get_netplan_files() {
    find "$CONFIG_DIR" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.off" \) | xargs -n1 basename | sort
}
# === Получение списка сетевых интерфейсов, кроме loopback ===
get_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo
}
# === Универсальное отображение меню выбора из массива ===
# Принимает список и печатает нумерованный список
show_menu() {
    local items=("$@")
    echo "Выберите элемент (или 0/q для выхода):"
    for i in "${!items[@]}"; do
        echo "$((i+1))) ${items[$i]}"
    done
}
# === Чтение и валидация выбора пользователя ===
read_user_choice() {
    local count=$1
    read -rp "> " choice

    # Проверка выхода по 0 или q
    if [[ "$choice" == "0" || "$choice" == "q" ]]; then
        return 1
    fi

    # Проверка на число в пределах допустимого диапазона
    if [[ ! $choice =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
        echo "Неверный выбор"
        return 1
    fi

    echo "$choice"
}
# === Выбор файла конфигурации из списка ===
select_file_from_list() {
    files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(get_netplan_files)

    # Проверка наличия файлов
    if [ ${#files[@]} -eq 0 ]; then
        echo "Нет доступных файлов"
        return 1
    fi

    # Отображение меню выбора
    while true; do
        show_menu "${files[@]}"
        choice=$(read_user_choice "${#files[@]}") || return 1
        REPLY="${files[$((choice - 1))]}"
        return 0
    done
}
# === Выбор сетевого интерфейса из списка ===
select_interface_from_list() {
    interfaces=()
    while IFS= read -r iface; do
        interfaces+=("$iface")
    done < <(get_interfaces)

    # Проверка наличия интерфейсов
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo "Нет доступных интерфейсов"
        return 1
    fi

    # Отображение меню выбора
    while true; do
        show_menu "${interfaces[@]}"
        choice=$(read_user_choice "${#interfaces[@]}") || return 1
        REPLY="${interfaces[$((choice - 1))]}"
        return 0
    done
}
# === Главное меню управления конфигурациями Netplan ===
manage_configs() {
    while true; do
        echo "=============================="
        echo "   Управление конфигурациями"
        echo "=============================="
        echo "1) Список конфигов"
        echo "2) Просмотреть все конфиги"
        echo "3) Редактировать конфиг"
        echo "4) Вкл / выкл конфиг (.yaml <-> .off)"
        echo "5) Установить права 600"
        echo "6) Резервное копирование"
        echo "7) Восстановление из копии"
        echo "8) Удалить конфиг"
        echo "9) Переименовать конфиг"
        echo "0) Назад"
        read -rp "> " sel

        case $sel in
            1)
                # Показать список конфигов
                files=()
                while IFS= read -r file; do
                   files+=("$file")
                done < <(get_netplan_files)

                if [ ${#files[@]} -eq 0 ]; then
                    echo "Нет доступных конфигов"
                else
                    echo "Файлы конфигурации в $CONFIG_DIR:"
                    for f in "${files[@]}"; do
                        echo "- $f"
                    done
                fi
                ;;
            2)
                echo "Просмотр всех конфигурационных файлов..."
                for file in "$CONFIG_DIR"/*.{yaml,off}; do
                    [[ -f "$file" ]] || continue
                    echo -e "\n===== $(basename "$file") ====="
                    cat "$file"
                done | less
                ;;
            3)
                # Редактировать выбранный конфиг
                select_file_from_list || continue
                file="$REPLY"
                $EDITOR "$CONFIG_DIR/$file" && sudo chmod 600 "$CONFIG_DIR/$file"
                ;;
            4)
                # Вкл / выкл конфиг
                select_file_from_list || continue
                file="$REPLY"
                if [[ $file == *.yaml ]]; then
                    mv "$CONFIG_DIR/$file" "$CONFIG_DIR/${file%.yaml}.off"
                    log_action "$file выключен"
                else
                    newname="${file%.off}.yaml"
                    mv "$CONFIG_DIR/$file" "$CONFIG_DIR/$newname"
                    sudo chmod 600 "$CONFIG_DIR/$newname"
                    log_action "$file включён"
                fi
                ;;
            5)
                # Установить права 600
                select_file_from_list || continue
                file="$REPLY"
                sudo chmod 600 "$CONFIG_DIR/$file"
                echo "Права 600 установлены для $file"
                log_action "chmod 600 для $file"
                ;;
            6)
                # Резервное копирование
                BACKUP_DIR="$CONFIG_DIR/backup_$(date +%F_%H-%M-%S)"
                mkdir -p "$BACKUP_DIR" && cp "$CONFIG_DIR"/*.yaml "$BACKUP_DIR" 2>/dev/null
                echo "Сохранено в $BACKUP_DIR"
                log_action "Бэкап в $BACKUP_DIR"
                ;;
            7)
                # Восстановление из резервной копии
                echo "Доступные резервные копии:"
                backups=()
                while IFS= read -r dir; do
                    backups+=("$dir")
                done < <(find "$CONFIG_DIR" -maxdepth 1 -type d -name "backup_*" | sort)

                if [ ${#backups[@]} -eq 0 ]; then echo "Нет копий"; continue; fi

                show_menu "${backups[@]}"
                choice=$(read_user_choice "${#backups[@]}") || continue
                backup_dir="${backups[$((choice - 1))]}"
                cp "$backup_dir"/*.yaml "$CONFIG_DIR" && sudo chmod 600 "$CONFIG_DIR"/*.yaml
                echo "Восстановлено из $backup_dir"
                log_action "Восстановление из $backup_dir"
                ;;
            8)
                # Удалить конфиг
                select_file_from_list || continue
                file="$REPLY"
                read -rp "Точно удалить $file? (y/n): " confirm
                if [[ $confirm == y ]]; then
                    rm "$CONFIG_DIR/$file"
                    echo "$file удалён."
                    log_action "Удалён конфиг $file"
                else
                    echo "Отменено."
                fi
                ;;
            9)
                # Переименовать конфиг
                select_file_from_list || continue
                file="$REPLY"

                read -rp "Новое имя (только имя, без расширения): " newname
                [[ -z "$newname" || "$newname" == "$file" ]] && echo "Отменено." && continue

                # Принудительно добавить расширение .off
                newname="${newname}.off"

                mv "$CONFIG_DIR/$file" "$CONFIG_DIR/$newname"
                log_action "Переименован $file -> $newname"
                echo "Переименовано: $file → $newname"
                ;;
            0) return ;;
        esac
    done
}
# === Управление сетевыми адаптерами с REPLY ===
manage_adapters() {
    while true; do
        echo "=============================="
        echo "     Сетевые адаптеры"
        echo "=============================="
        echo "1) Показать адаптеры"
        echo "2) Поднять адаптер"
        echo "3) Выключить адаптер"
        echo "4) Настроить Wake-on-LAN (WOL)"
        echo "5) Информация о драйвере и модуле"
        echo "0) Назад"
        read -rp "> " sel

        case $sel in
            1)
                ip -c a show
                ;;
            2)
                select_interface_from_list || continue
                iface="$REPLY"
                sudo ip link set "$iface" up && echo "$iface включен"
                ;;
            3)
                select_interface_from_list || continue
                iface="$REPLY"
                sudo ip link set "$iface" down && echo "$iface выключен"
                ;;
            4)
                select_interface_from_list || continue
                iface="$REPLY"
                sudo ethtool -s "$iface" wol g && echo "WOL включён на $iface"
                ;;
            5)
                select_interface_from_list || continue
                iface="$REPLY"
                ethtool -i "$iface" 2>/dev/null || echo "ethtool не установлен или ошибка"
                ;;
            0)
                return
                ;;
            *)
                echo "Неверный выбор"
                ;;
        esac
    done
}
# === Проверка и применение конфигураций Netplan ===
apply_or_check() {
    echo "=============================="
    echo "  Применить / Проверить конфиги"
    echo "=============================="
    echo "1) Проверка на 20 сек (netplan try)"
    echo "2) Проверка на 60 сек"
    echo "3) Проверка на 120 сек"
    echo "4) Применить + перезапустить рендерер"
    echo "5) Проверить синтаксис (без применения)"
    echo "0) Назад"
    read -rp "> " choice

    case "$choice" in
        1)
            sudo netplan try --timeout 20
            log_action "netplan try (20 сек)"
            ;;
        2)
            sudo netplan try --timeout 60
            log_action "netplan try (60 сек)"
            ;;
        3)
            sudo netplan try --timeout 120
            log_action "netplan try (120 сек)"
            ;;
        4)
            sudo netplan apply
            log_action "netplan apply + перезапуск рендерера"

            renderer=$(grep -i "renderer:" /etc/netplan/*.yaml | head -n1 | awk '{print $2}')
            if [[ "$renderer" == "networkd" ]]; then
                echo "[+] Перезапуск systemd-networkd..."
                sudo systemctl restart systemd-networkd
            elif [[ "$renderer" == "NetworkManager" ]]; then
                echo "[+] Перезапуск NetworkManager..."
                sudo systemctl restart NetworkManager
            else
                echo "[!] Рендерер не определён, перезапуск пропущен."
            fi
            ;;
        5)
            echo "[i] Проверка синтаксиса netplan конфигураций..."
            sudo netplan generate --debug
            log_action "netplan generate (проверка синтаксиса)"
            ;;
        0|q)
            return
            ;;
        *)
            echo "Неверный выбор"
            ;;
    esac
}

# === Просмотр логов и диагностика сети ===
view_logs() {
    while true; do
        echo "=============================="
        echo " Логи и диагностика сети"
        echo "=============================="
        echo "1) Лог systemd-networkd"
        echo "2) Лог netplan (journalctl)"
        echo "3) dmesg по сетевым событиям"
        echo "4) Лог NetworkManager"
        echo "5) Проверка подключения (ping 8.8.8.8)"
        echo "0) Назад"
        read -rp "> " sel

        case $sel in
            1)
                journalctl -xeu systemd-networkd | tail -n 30
                ;;
            2)
                journalctl -xe | grep netplan | tail -n 30
                ;;
            3)
                dmesg | grep -iE 'eth|wlan|enp|link'
                ;;
            4)
                journalctl -u NetworkManager | tail -n 30
                ;;
            5)
                ping -c 4 8.8.8.8
                ;;
            0)
                return
                ;;
            *)
                echo "Неверный выбор"
                ;;
        esac
    done
}
# === Вывод всех интерфейсов с MAC ===
show_interfaces_with_mac() {
    echo ""
    echo "| Интерфейс | MAC-адрес         | on/off | IP-адрес             | Драйвер  |"
    echo "|-----------|-------------------|--------|----------------------|----------|"

    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null)
        state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null)
        ipaddr=$(ip -4 addr show dev "$iface" | awk '/inet / {print $2}' | cut -d/ -f1)
        driver=$(ethtool -i "$iface" 2>/dev/null | grep driver | awk '{print $2}')

        [[ "$state" == "up" ]] && status="↑" || status="↓"
        ipaddr="${ipaddr:-—}"
        driver="${driver:-—}"

        printf "| %-9s | %-17s | %-8s | %-20s | %-8s |\n" \
            "$iface" "$mac" "$status" "$ipaddr" "$driver"
    done

    echo ""
}

# === Главное меню Netplan Manager ===
main_menu() {
    while true; do
        echo "=============================="
        echo "       МЕНЕДЖЕР NETPLAN"
        echo "=============================="
        echo "1) Управление конфигурациями"
        echo "2) Сетевые адаптеры"
        echo "3) Настройки подключения (расширенные)"
        echo "4) Применить / Проверить конфиги"
        echo "5) Просмотр логов и диагностика"
        echo "6) Создать конфиг вручную"
        echo "7) Создать конфиг из шаблона"
        echo "8) Выход"
        read -rp "> " main
        case $main in
            1) manage_configs ;;
            2) manage_adapters ;;
            3) echo "[!] Ветка расширенных опций пока отключена" ;;
            4) apply_or_check ;;
            5) view_logs ;;
            6)  show_interfaces_with_mac
                netplan_constructor ;;   # <-- твой конструктор
            7)  show_interfaces_with_mac
                use_template ;;          # <-- функция выбора шаблона
            8) exit 0 ;;
            *) echo "Неверный выбор" ;;
        esac
    done
}
# === Точка входа ===
main_menu


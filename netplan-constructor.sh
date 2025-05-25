#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# === Путь до директории конфигов Netplan ===
CONFIG_DIR="/etc/netplan"
EDITOR="nano"
TEMPLATE_DIR="/etc/netplan/netplan-template"


# Функция: использование шаблона ===
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
            config+="\n  ethernets:\n    $iface:\n      dhcp4: true"
            ;;
        2)
            read -rp "IP-адрес (CIDR): " ip
            [[ "$ip" == "q" || "$ip" == "0" ]] && return
            read -rp "Шлюз: " gw
            [[ "$gw" == "q" || "$gw" == "0" ]] && return
            read -rp "DNS (через запятую): " dns
            [[ "$dns" == "q" || "$dns" == "0" ]] && return
            config+="\n  ethernets:\n    $iface:\n      dhcp4: false\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            ;;
        3)
            read -rp "SSID: " ssid
            [[ "$ssid" == "q" || "$ssid" == "0" ]] && return
            read -rp "Пароль или EAP: " pass
            [[ "$pass" == "q" || "$pass" == "0" ]] && return
            config+="\n  wifis:\n    $iface:\n      access-points:\n        \"$ssid\":\n          password: \"$pass\"\n      dhcp4: true"
            ;;
        4)
            read -rp "ID VLAN: " vlan_id
            read -rp "Физический интерфейс: " link
            read -rp "IP-адрес (CIDR): " ip
            read -rp "Шлюз: " gw
            read -rp "DNS (через запятую): " dns
            config+="\n  ethernets:\n    $link: {}\n  vlans:\n    $iface:\n      id: $vlan_id\n      link: $link\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
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
                read -rp "Шлюз: " gw; [[ "$gw" == "q" || "$gw" == "0" ]] && return
                read -rp "DNS (через запятую): " dns; [[ "$dns" == "q" || "$dns" == "0" ]] && return
                config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            fi
            ;;
        6)
            # DMZ (VLAN или Bridge)
            echo "Выберите базу DMZ:"
            echo "1) VLAN"
            echo "2) Bridge"
            read -rp "> " dmz_mode
            [[ "$dmz_mode" == "q" || "$dmz_mode" == "0" ]] && return

            if [[ $dmz_mode == 1 ]]; then
                # DMZ на базе VLAN: выбор физического интерфейса из списка
                read -rp "ID VLAN: " vlan_id
                [[ "$vlan_id" == "q" || "$vlan_id" == "0" ]] && return

                mapfile -t physifs < <(get_interfaces)
                if [ ${#physifs[@]} -eq 0 ]; then
                    echo "Нет интерфейсов"
                    return
                fi
                echo "Выберите физический интерфейс для DMZ (номер):"
                for i in "${!physifs[@]}"; do
                    echo "$((i+1))) ${physifs[$i]}"
                done
                read -rp "> " sel
                [[ "$sel" == "q" || "$sel" == "0" ]] && return
                if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#physifs[@]} )); then
                    echo "Неверный выбор"
                    return
                fi
                link=${physifs[$((sel-1))]}

                read -rp "IP-адрес: " ip
                [[ "$ip" == "q" || "$ip" == "0" ]] && return
                read -rp "Шлюз: " gw
                [[ "$gw" == "q" || "$gw" == "0" ]] && return
                read -rp "DNS (через запятую): " dns
                [[ "$dns" == "q" || "$dns" == "0" ]] && return

                config+="\n  ethernets:\n    $link: {}\
                            \n  vlans:\n    $iface:\n      id: $vlan_id\
                            \n      link: $link\
                            \n      addresses: [$ip]\
                            \n      routes:\n        - to: default\n          via: $gw\
                            \n      nameservers:\n        addresses: [${dns//,/ }]"
            elif [[ $dmz_mode == 2 ]]; then
                …
            elif [[ $dmz_mode == 2 ]]; then
                # DMZ на базе Bridge
                mapfile -t physifs < <(get_interfaces)
                if [ ${#physifs[@]} -eq 0 ]; then
                    echo "Нет интерфейсов"
                    return
                fi
                echo "Выберите интерфейсы для DMZ-моста (через запятую):"
                for i in "${!physifs[@]}"; do
                    echo "$((i+1))) ${physifs[$i]}"
                done
                read -rp "> " sel
                [[ "$sel" == "q" || "$sel" == "0" ]] && return

                dmz_ifaces=()
                IFS=',' read -ra nums <<< "$sel"
                for n in "${nums[@]}"; do
                    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#physifs[@]} )); then
                        dmz_ifaces+=("${physifs[$((n-1))]}")
                    fi
                done
                [[ ${#dmz_ifaces[@]} -eq 0 ]] && echo "Не выбрано" && return
                dmz_iflist=$(IFS=,; echo "${dmz_ifaces[*]}")

                # Ввод сетевых параметров
                read -rp "IP-адрес: " ip
                [[ "$ip" == "q" || "$ip" == "0" ]] && return
                read -rp "Шлюз: " gw
                [[ "$gw" == "q" || "$gw" == "0" ]] && return
                read -rp "DNS (через запятую): " dns
                [[ "$dns" == "q" || "$dns" == "0" ]] && return

                # Построение блока DMZ-моста с правильными отступами
                config+="\n  bridges:\n    $iface:\n      wakeonlan: true\n      interfaces: [${dmz_iflist// /, }]\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
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
                read -rp "PrivateKey (файл /etc/wireguard/private.key): " pkey
                [[ "$pkey" == "q" || "$pkey" == "0" ]] && return
                read -rp "Peer PublicKey: " peerkey
                read -rp "Endpoint (IP:port): " endpoint
                read -rp "Allowed IPs (через запятую): " allowed

                config+="\n  tunnels:\n    $iface:\n      mode: wireguard\n      addresses: [10.0.0.2/24]\n      key: $(cat $pkey)\n      peers:\n        - key: $peerkey\n          endpoint: $endpoint\n          allowed-ips: [${allowed//,/ }]"

            elif [[ "$vpn_mode" == "2" ]]; then
                echo "Выберите режим OpenVPN подключения:"
                echo "1) DHCP (выдаётся VPN-сервером)"
                echo "2) Статический IP внутри VPN-сети"
                read -rp "> " open_mode
                [[ "$open_mode" == "q" || "$open_mode" == "0" ]] && return

                config+="\n  ethernets:\n    $iface:"
                if [[ "$open_mode" == "1" ]]; then
                    config+="\n      dhcp4: true"
                elif [[ "$open_mode" == "2" ]]; then
                    read -rp "IP-адрес: " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
                    read -rp "Шлюз (внутри VPN): " gw
                    read -rp "DNS-серверы: " dns
                    config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
                else
                    echo "Неверный выбор"
                    return
                fi
            else
                echo "Неверный выбор"
                return
            fi
            ;;
        8)
            read -rp "Имя VRF: " vrfname
            [[ "$vrfname" == "q" || "$vrfname" == "0" ]] && return
            read -rp "ID таблицы маршрутизации (table ID): " tableid
            [[ "$tableid" == "q" || "$tableid" == "0" ]] && return
            read -rp "Сетевой интерфейс для VRF: " physif
            [[ "$physif" == "q" || "$physif" == "0" ]] && return
            read -rp "IP-адрес для $physif: " ip; [[ "$ip" == "q" || "$ip" == "0" ]] && return
            read -rp "Шлюз: " gw; [[ "$gw" == "q" || "$gw" == "0" ]] && return
            read -rp "DNS (через запятую): " dns; [[ "$dns" == "q" || "$dns" == "0" ]] && return

            config+="\n  vrfs:\n    $vrfname:\n      table: $tableid"
            config+="\n  ethernets:\n    $physif:\n      vrf: $vrfname\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            ;;

        9)
            read -rp "Имя интерфейса VXLAN (например, vxlan100): " vxname
            [[ "$vxname" == "q" || "$vxname" == "0" ]] && return
            read -rp "ID VXLAN: " vxid
            read -rp "Интерфейс-носитель (обычно ethX): " parent
            read -rp "Локальный IP (local): " localip
            read -rp "Удалённый IP (remote): " remoteip
            read -rp "Мультикаст группа (опц.): " mcast
            read -rp "Порт (по умолчанию 4789): " port
            port=${port:-4789}
            read -rp "MTU (опц.): " mtu

            config+="\n  tunnels:\n    $vxname:\n      mode: vxlan\n      id: $vxid\n      link: $parent\n      local: $localip\n      remote: $remoteip\n      port: $port"
            [[ -n "$mcast" ]] && config+="\n      group: $mcast"
            [[ -n "$mtu" ]] && config+="\n      mtu: $mtu"
            ;;

        10)
            read -rp "Имя OVS bridge (например, ovs-br0): " ovsbr
            [[ "$ovsbr" == "q" || "$ovsbr" == "0" ]] && return
            mapfile -t ovsifs < <(get_interfaces)
            if [ ${#ovsifs[@]} -eq 0 ]; then echo "Нет доступных интерфейсов"; return; fi
            echo "Выберите интерфейсы для OVS bridge (через запятую):"
            for i in "${!ovsifs[@]}"; do echo "$((i+1))) ${ovsifs[$i]}"; done
            read -rp "> " sel
            [[ "$sel" == "q" || "$sel" == "0" ]] && return
            ovslist=(); IFS=',' read -ra nums <<< "$sel"
            for n in "${nums[@]}"; do
                [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#ovsifs[@]} )) && ovslist+=("${ovsifs[$((n-1))]}")
            done
            [[ ${#ovslist[@]} -eq 0 ]] && echo "Ничего не выбрано" && return
            ovsjoined=$(IFS=,; echo "${ovslist[*]}")
            read -rp "IP-адрес (CIDR): " ip
            [[ "$ip" == "q" || "$ip" == "0" ]] && return
            read -rp "Шлюз: " gw
            [[ "$gw" == "q" || "$gw" == "0" ]] && return
            read -rp "DNS (через запятую): " dns
            [[ "$dns" == "q" || "$dns" == "0" ]] && return

            config+="\n  openvswitch:\n    bridges:\n      $ovsbr:\n        interfaces: [${ovsjoined// /, }]\n  ethernets:\n    $ovsbr:\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            ;;

        11)
            read -rp "Имя интерфейса SR-IOV (например, enp3s0f0): " sriov_if
            [[ "$sriov_if" == "q" || "$sriov_if" == "0" ]] && return
            read -rp "Количество виртуальных функций (VF): " vf_count
            [[ "$vf_count" == "q" || "$vf_count" == "0" ]] && return
            read -rp "IP-адрес (CIDR): " ip
            [[ "$ip" == "q" || "$ip" == "0" ]] && return
            read -rp "Шлюз: " gw
            [[ "$gw" == "q" || "$gw" == "0" ]] && return
            read -rp "DNS-серверы: " dns
            [[ "$dns" == "q" || "$dns" == "0" ]] && return

            config+="\n  ethernets:\n    $sriov_if:\n      sriov: true\n      virtual-function-count: $vf_count\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            ;;

        12)
            read -rp "Имя veth-интерфейса (например, veth0): " veth1
            [[ "$veth1" == "q" || "$veth1" == "0" ]] && return
            read -rp "Имя пары veth-интерфейса (например, veth1): " veth2
            [[ "$veth2" == "q" || "$veth2" == "0" ]] && return
            read -rp "IP-адрес для $veth1 (CIDR): " ip
            [[ "$ip" == "q" || "$ip" == "0" ]] && return
            read -rp "Шлюз: " gw
            [[ "$gw" == "q" || "$gw" == "0" ]] && return
            read -rp "DNS-серверы: " dns
            [[ "$dns" == "q" || "$dns" == "0" ]] && return

            config+="\n  ethernets:\n    $veth1:\n      match:\n        name: $veth1\n      set-name: $veth1\n      peer: $veth2\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            config+="\n    $veth2:\n      match:\n        name: $veth2\n      set-name: $veth2"
            ;;

        13)
            echo "Выберите тип модемного подключения:"
            echo "1) DHCP (PPP/LTE выдаёт IP)"
            echo "2) Статический IP через модем"
            read -rp "> " mode
            [[ "$mode" == "q" || "$mode" == "0" ]] && return

            read -rp "Имя интерфейса модема (например, wwan0): " modem_if
            [[ "$modem_if" == "q" || "$modem_if" == "0" ]] && return

            config+="\n  ethernets:\n    $modem_if:"

            if [[ "$mode" == "1" ]]; then
                config+="\n      dhcp4: true"
            elif [[ "$mode" == "2" ]]; then
                read -rp "IP-адрес: " ip
                read -rp "Шлюз: " gw
                read -rp "DNS (через запятую): " dns
                config+="\n      addresses: [$ip]\n      routes:\n        - to: default\n          via: $gw\n      nameservers:\n        addresses: [${dns//,/ }]"
            else
                echo "Неверный выбор"
                return
            fi

            read -rp "Указать APN (Access Point Name)? (y/n): " apn_ask
            if [[ "$apn_ask" == "y" ]]; then
                read -rp "APN: " apn
                config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ access-point: $apn")
            fi

            read -rp "Указать PIN-код SIM? (y/n): " pin_ask
            if [[ "$pin_ask" == "y" ]]; then
                read -rp "PIN-код: " pin
                config=$(echo -e "$config" | sed "/^ *$modem_if:/a \ \ \ \ sim-pin: $pin")
            fi
            ;;



    esac

    read -rp "Добавить MAC-адрес? (y/n): " mac_yes
    if [[ $mac_yes == y ]]; then
        read -rp "MAC-адрес: " mac
        config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ macaddress: $mac")
    fi

    read -rp "Добавить MTU? (y/n): " mtu_yes
    if [[ $mtu_yes == y ]]; then
        read -rp "MTU: " mtu
        config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ mtu: $mtu")
    fi

    read -rp "Добавить Wake-on-LAN? (y/n): " wol_yes
    if [[ $wol_yes == y ]]; then
        config=$(echo -e "$config" | sed "/^ *$iface:/a \ \ \ \ wakeonlan: true")
    fi

    echo -e "\nПредпросмотр конфигурации:\n=========================="
    echo -e "$config"
    echo "=========================="

    read -rp "Имя файла (без .yaml): " fname
    [[ "$fname" == "q" || "$fname" == "0" || -z "$fname" ]] && return

    file="$CONFIG_DIR/${fname}.yaml"

    read -rp "Сохранить и применить? (y/n): " confirm
    [[ "$confirm" == "q" || "$confirm" == "0" ]] && return

    if [[ $confirm == y ]]; then
        echo -e "$config" > "$file"
        sudo chmod 600 "$file"
        log_action "Создан конфиг $file через конструктор"
        netplan try --timeout 30 || echo "Ошибка применения. Проверьте вручную."
    else
        echo "Отменено."
    fi
}

# === Функция: логирование действий ===
log_action() {
    local timestamp
    timestamp=$(date "+%F %T")
    echo "[$timestamp] $1" >> /var/log/netplan-constructor.log
}
# === Функция: получение списка интерфейсов ===
get_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo
}

main_menu() {
    while true; do
        clear
        echo "=============================="
        echo "     КОНСТРУКТОР NETPLAN"
        echo "=============================="
        echo "1) Создать *.yaml вручную (интерактивно)"
        echo "2) Создать *.yaml, используя шаблон"
        echo "0) Выход"
        read -rp "> " choice

        case "$choice" in
            1)
                netplan_constructor
                ;;
            2)
                use_template
                ;;
            0|q)
                echo "Выход."
                exit 0
                ;;
            *)
                echo "Неверный выбор"; sleep 1
                ;;
        esac
    done
}
# Запуск конструктора
main_menu

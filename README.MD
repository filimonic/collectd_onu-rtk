# Collect Realtek xPON ONU/ONT data to [collectd][1]

This tool takes metrics from Realtek ONUs via telnet and reports them to [collectd][1].

It is developed to run [OpenWrt][3] mainly, this explains strange [dependencies](#openwrt-dependencies).

## Metrics

- `collectd_onu_transceiver_temperature`
- `collectd_onu_transceiver_voltage`
- `collectd_onu_transceiver_bias_current`
- `collectd_onu_transceiver_rx_signal_power`
- `collectd_onu_transceiver_tx_power`
- `uptime`

## Tested devices

- [BDCOM GP1702-1G][dev-001]

[1]: https://collectd.org
[3]: https://openwrt.org/
[dev-001]: https://bdcom.cn/data_onu/82.html

## Prerequisites

- You need to access your ONU from your OpenWrt box through network
- You need to be able to telnet to it
- You need to be able to authenticate with admin accounts in telnet (for BDCOM: username is `admin` and password is `super&123`)
- You need to be able to run `diag pon get transceiver temperature` command and get temperature

## Install on OpenWrt

- Install dependencies:

  ```ash
  opkg update
  opkg install collectd-mod-exec telnet-bsd sexpect
  ```

- Download shell script, do **not** make it executable:

  ```ash
  wget -O /usr/lib/collectd/onu_rtk.sh https://github.com/filimonic/collectd_onu-rtk/releases/latest/download/onu_rtk.sh
  ```

- Configure collectd

  - Load plugin `exec` in `/etc/collectd.conf`.
    Normally, `exec` plugin expects long-running scripts and programs that periodically
    report data to plugin. Plugin does not expects that executed program will exit
    immediately after reporting metrics. If program exited, `collectd` will attempt to
    start it again next global `Interval`. If you have small global `Interval` value, it
    is recomended to specify few times higher value for `exec` plugin in `LoadPlugin`
    section.
    ```
    <LoadPlugin "exec">
      # Set interval to 120 seconds,
      # this should keep our device safe from
      # exec restarts some programs too often
      # in case they exit (they should not).
      Interval 120
    </LoadPlugin>
    ```
  - Add `exec` plugin section in `/etc/collectd.conf`. Here we can specify number
    of seconds for script to collect data as parameter.
    ```
    <Plugin "exec">
      Exec "nobody:nogroup" "/bin/ash" "/usr/lib/collectd/onu_rtk.sh" "60"
    </Plugin>
    ```
  - Configure your ONUs. Please note that, as we running as `nobody`, we should allow
    every user on your OpenWrt box to read this data.

    - Create new config file and give it read permissions:
      ```
      echo "package 'collectd-onu_rtk'" > /etc/config/collectd-onu_rtk
      chmod a+r /etc/config/collectd-onu_rtk
      ```
    - Register new ONU:
      ```
      uci add collectd-onu_rtk onu_item
      uci set collectd-onu_rtk.@onu_item[-1].instance_name='dongle_name_or_isp_name'
      uci set collectd-onu_rtk.@onu_item[-1].server='192.168.1.1'
      uci set collectd-onu_rtk.@onu_item[-1].username='admin'
      uci set collectd-onu_rtk.@onu_item[-1].password='super&123'
      uci commit collectd-onu_rtk
      ```
    - Restart collectd
      ```
      /etc/init.d/collectd restart
      ```

## OpenWrt dependencies

I assume `collectd` is already running on your OpenWrt device.

To run this with `collectd`, you need to install:

- `collectd-mod-exec`: 26 KiB.
- `telnet-bsd`: 46 KiB.
- `sexpect`: 24 KiB.

import os from 'os'
import v8 from 'v8'
import fs from 'fs'
import si from 'systeminformation' // Library untuk mendapatkan informasi sistem seperti disk dan network stats

export default (handler) => {
    handler.reg({
        cmd: ['ping', 'server',],
        tags: 'main',
        desc: 'Detail server',
        run: async (m, { func }) => {
            const used = process.memoryUsage()
            const cpus = os.cpus().map(cpu => {
                cpu.total = Object.keys(cpu.times).reduce(
                    (last, type) => last + cpu.times[type],
                    0
                )
                return cpu
            })
            const cpu = cpus.reduce(
                (last, cpu, _, { length }) => {
                    last.total += cpu.total
                    last.speed += cpu.speed / length
                    last.times.user += cpu.times.user
                    last.times.nice += cpu.times.nice
                    last.times.sys += cpu.times.sys
                    last.times.idle += cpu.times.idle
                    last.times.irq += cpu.times.irq
                    return last
                },
                {
                    speed: 0,
                    total: 0,
                    times: {
                        user: 0,
                        nice: 0,
                        sys: 0,
                        idle: 0,
                        irq: 0
                    }
                }
            )
            let heapStat = v8.getHeapStatistics()
            const x = "`"
            const myip = await func.fetchJson("https://ipinfo.io/json")
            function hideIp(ip) {
                const ipSegments = ip.split(".")
                if (ipSegments.length === 4) {
                    ipSegments[2] = "***"
                    ipSegments[3] = "***"
                    return ipSegments.join(".")
                } else {
                    throw new Error("Invalid IP address")
                }
            }
            const ips = hideIp(myip.ip)
            const resp = `${(Date.now() - new Date(m.timestamps * 1000)) / 1000
                } Detik`

            // Disk Usage
            const diskInfo = await si.fsSize()

            // Network Stats
            const networkStats = await si.networkStats()

            let teks = `${x}INFO SERVER${x}
- Speed Respons: _${resp}_
- Hostname: _amiruldev_
- CPU Core: _${cpus.length}_
- Platform : _${os.platform()}_
- OS : _${os.version()} / ${os.release()}_
- Arch: _${os.arch()}_
- Ram: _${func.formatSize(
                os.totalmem() - os.freemem()
            )}_ / _${func.formatSize(os.totalmem())}_

${x}PROVIDER INFO${x}
- IP: ${ips}
- Region : _${myip.region} ${myip.country}_
- ISP : _${myip.org}_

${x}DISK USAGE${x}
- Total Disk Space: _${func.formatSize(diskInfo[0].size)}_
- Used Disk Space: _${func.formatSize(diskInfo[0].used)}_
- Free Disk Space: _${func.formatSize(diskInfo[0].available)}_
- Disk Mount: _${diskInfo[0].mount}_

${x}NETWORK STATS${x}
- Interface: _${networkStats[0].iface}_
- RX (Received): _${func.formatSize(networkStats[0].rx_bytes)} bytes_
- TX (Transmitted): _${func.formatSize(networkStats[0].tx_bytes)} bytes_

${x}RUNTIME OS${x}
- _${func.runtime(os.uptime())}_

${x}RUNTIME BOT${x}
- _${func.runtime(process.uptime())}_

${x}NODE MEMORY USAGE${x}
${Object.keys(used)
                    .map(
                        (key, _, arr) =>
                            `*- ${key.padEnd(
                                Math.max(...arr.map(v => v.length)),
                                " "
                            )} :* ${func.formatSize(used[key])}`
                    )
                    .join("\n")}
*- Heap Executable :* ${func.formatSize(heapStat?.total_heap_size_executable)}
*- Physical Size :* ${func.formatSize(heapStat?.total_physical_size)}
*- Available Size :* ${func.formatSize(heapStat?.total_available_size)}
*- Heap Limit :* ${func.formatSize(heapStat?.heap_size_limit)}
*- Malloced Memory :* ${func.formatSize(heapStat?.malloced_memory)}
*- Peak Malloced Memory :* ${func.formatSize(heapStat?.peak_malloced_memory)}
*- Does Zap Garbage :* ${func.formatSize(heapStat?.does_zap_garbage)}
*- Native Contexts :* ${func.formatSize(heapStat?.number_of_native_contexts)}
*- Detached Contexts :* ${func.formatSize(
                        heapStat?.number_of_detached_contexts
                    )}
*- Total Global Handles :* ${func.formatSize(
                        heapStat?.total_global_handles_size
                    )}
*- Used Global Handles :* ${func.formatSize(
                        heapStat?.used_global_handles_size)}
${cpus[0]
                    ? `

*_Total CPU Usage_*
${cpus[0].model.trim()} (${cpu.speed} MHZ)\n${Object.keys(cpu.times)
                        .map(
                            type =>
                                `*- ${(type + "*").padEnd(6)}: ${(
                                    (100 * cpu.times[type]) /
                                    cpu.total
                                ).toFixed(2)}%`
                        )
                        .join("\n")}

*_CPU Core(s) Usage (${cpus.length} Core CPU)_*
${cpus
                        .map(
                            (cpu, i) =>
                                `${i + 1}. ${cpu.model.trim()} (${cpu.speed} MHZ)\n${Object.keys(
                                    cpu.times
                                )
                                    .map(
                                        type =>
                                            `*- ${(type + "*").padEnd(6)}: ${(
                                                (100 * cpu.times[type]) /
                                                cpu.total
                                            ).toFixed(2)}%`
                                    )
                                    .join("\n")}`
                        )
                        .join("\n\n")}`
                    : ""
                }
`.trim()
            m.reply(teks)
        }
    })
        }

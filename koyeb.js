import os from 'os'
import v8 from 'v8'
import fs from 'fs'

export default (handler) => {
  handler.reg({
    cmd: ['koyeb'],
    tags: 'main',
    desc: 'Detail server gratisan koyeb',
    run: async (m, { func }) => {
      // Memory and CPU usage information
      const usedMemory = process.memoryUsage()
      const cpus = os.cpus().map(cpu => ({
        ...cpu,
        total: Object.values(cpu.times).reduce((total, time) => total + time, 0)
      }))
      
      const cpuSummary = cpus.reduce((summary, cpu, _, { length }) => {
        summary.total += cpu.total
        summary.speed += cpu.speed / length
        Object.keys(cpu.times).forEach(key => summary.times[key] += cpu.times[key])
        return summary
      }, {
        speed: 0,
        total: 0,
        times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 }
      })

      const heapStats = v8.getHeapStatistics()
      const x = "`"
      const myip = await func.fetchJson("https://ipinfo.io/json")
      
      function hideIp(ip) {
        const ipSegments = ip.split(".")
        if (ipSegments.length === 4) {
          ipSegments[2] = "***"
          ipSegments[3] = "***"
          return ipSegments.join(".")
        } else throw new Error("Invalid IP address")
      }

      const ipHidden = hideIp(myip.ip)
      const responseTime = `${(Date.now() - new Date(m.timestamps * 1000)) / 1000} Detik`

      // Disk Information
      const rootDirStats = fs.statSync("/") // Root directory info
      const totalDiskSpace = rootDirStats.size
      const freeDiskSpace = os.freemem()
      const usedDiskSpace = totalDiskSpace - freeDiskSpace

      // Node.js and System Information
      const nodeVersion = process.versions.node
      const v8Version = process.versions.v8
      const osInfo = {
        name: os.type(),
        release: os.release(),
        arch: os.arch(),
        platform: os.platform(),
        version: os.version(),
      }
      const hardwareInfo = {
        cpuCount: cpus.length,
        cpuSpeed: cpus[0]?.speed,
        totalMemory: os.totalmem(),
        freeMemory: os.freemem()
      }

      let infoText = `${x}INFO SERVER${x}
- Speed Respons: _${responseTime}_
- Hostname: _Brogalan Blora_
- CPU Core: _${hardwareInfo.cpuCount}_
- Platform : _${osInfo.platform}_
- OS : _${osInfo.version} / ${osInfo.release}_
- Arch: _${osInfo.arch}_
- Ram: _${func.formatSize(hardwareInfo.totalMemory - hardwareInfo.freeMemory)}_ / _${func.formatSize(hardwareInfo.totalMemory)}_

${x}PROVIDER INFO${x}
- IP: ${ipHidden}
- Region : _${myip.region} ${myip.country}_
- ISP : _${myip.org}_

${x}RUNTIME OS${x}
- _${func.runtime(os.uptime())}_

${x}RUNTIME BOT${x}
- _${func.runtime(process.uptime())}_

${x}DISK USAGE${x}
- Total Disk: _${func.formatSize(totalDiskSpace)}_
- Used Disk: _${func.formatSize(usedDiskSpace)}_
- Free Disk: _${func.formatSize(freeDiskSpace)}_

${x}NODE MEMORY USAGE${x}
${Object.entries(usedMemory)
  .map(([key, value]) => `*- ${key.padEnd(12)} :* ${func.formatSize(value)}`)
  .join("\n")}
*- Heap Executable :* ${func.formatSize(heapStats?.total_heap_size_executable)}
*- Physical Size :* ${func.formatSize(heapStats?.total_physical_size)}
*- Available Size :* ${func.formatSize(heapStats?.total_available_size)}
*- Heap Limit :* ${func.formatSize(heapStats?.heap_size_limit)}
*- Malloced Memory :* ${func.formatSize(heapStats?.malloced_memory)}
*- Peak Malloced Memory :* ${func.formatSize(heapStats?.peak_malloced_memory)}
*- Native Contexts :* ${heapStats?.number_of_native_contexts}
*- Detached Contexts :* ${heapStats?.number_of_detached_contexts}
*- Total Global Handles :* ${func.formatSize(heapStats?.total_global_handles_size)}
*- Used Global Handles :* ${func.formatSize(heapStats?.used_global_handles_size)}

${cpus[0]
  ? `
*_Total CPU Usage_*
${cpus[0].model.trim()} (${cpuSummary.speed} MHZ)
${Object.keys(cpuSummary.times)
  .map(type => `*- ${type.padEnd(6)}: ${(100 * cpuSummary.times[type] / cpuSummary.total).toFixed(2)}%`)
  .join("\n")}

*_CPU Core(s) Usage (${hardwareInfo.cpuCount} Core CPU)_*
${cpus
  .map((cpu, i) => `${i + 1}. ${cpu.model.trim()} (${cpu.speed} MHZ)
${Object.keys(cpu.times)
  .map(type => `*- ${type.padEnd(6)}: ${(100 * cpu.times[type] / cpu.total).toFixed(2)}%`)
  .join("\n")}`)
  .join("\n\n")}` 
  : ""
}
`.trim()
      m.reply(infoText)
    }
  })
}

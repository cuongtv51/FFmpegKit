import Foundation
// import PackagePlugin

do {
    try BuildFFmpeg.performCommand(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    print(error.localizedDescription)
    exit(0)
}

enum BuildFFmpeg {
    // @main struct BuildFFmpeg: CommandPlugin {
//    func performCommand(context _: PluginContext, arguments: [String]) throws {
//        performCommand(arguments: arguments)
//    }
    static func performCommand(arguments: [String]) throws {
        if Utility.shell("which brew") == nil {
            print("""
            You need to run the script first
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """)
            return
        }
        if Utility.shell("which pkg-config") == nil {
            Utility.shell("brew install pkg-config")
        }
        let path = URL.currentDirectory + "Script"
        if !FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: nil)
        }
        FileManager.default.changeCurrentDirectoryPath(path.path)
        BaseBuild.platforms = arguments.compactMap { argument in
            if argument.hasPrefix("platform=") {
                let value = String(argument.suffix(argument.count - "platform=".count))
                return PlatformType(rawValue: value)
            } else {
                return nil
            }
        }
        if BaseBuild.platforms.isEmpty {
            BaseBuild.platforms = PlatformType.allCases
        }
        if arguments.firstIndex(of: "enable-openssl") != nil {
            try BuildOpenSSL().buildALL()
        }
        if arguments.firstIndex(of: "enable-libsrt") != nil {
            try BuildSRT().buildALL()
        }

        if arguments.firstIndex(of: "enable-libass") != nil {
            //            try BuildPng().buildALL()
            try BuildFreetype().buildALL()
            try BuildFribidi().buildALL()
            try BuildHarfbuzz().buildALL()
            try BuildASS().buildALL()
        }
        if arguments.firstIndex(of: "enable-libsmbclient") != nil {
            try BuildGmp().buildALL()
            try BuildNettle().buildALL()
            try BuildGnutls().buildALL()
            try BuildSmbclient().buildALL()
        }
        if arguments.firstIndex(of: "disable-ffmpeg") == nil {
            try BuildFFMPEG(arguments: arguments).buildALL()
        }
        if arguments.firstIndex(of: "enable-mpv") != nil {
            try BuildMPV().buildALL()
        }
    }
}

private enum Library: String, CaseIterable {
    case FFmpeg, freetype, fribidi, harfbuzz, libass, libpng, mpv, openssl, srt, smbclient, gnutls, gmp, nettle
    var version: String {
        switch self {
        case .FFmpeg:
            return "n5.1.2"
        case .freetype:
            return "VER-2-12-1"
        case .fribidi:
            return "v1.0.12"
        case .harfbuzz:
            return "5.3.1"
        case .libass:
            return "0.17.0"
        case .libpng:
            return "v1.6.39"
        case .mpv:
            return "v0.35.0"
        case .openssl:
            return "openssl-3.0.7"
        case .srt:
            return "v1.5.1"
        case .smbclient:
            return "samba-4.17.5"
        case .gnutls:
            return "3.7.8"
        case .nettle:
            return "nettle_3.8.1_release_20220727"
        case .gmp:
            return "v6.2.1"
        }
    }

    var url: String {
        switch self {
        case .libpng:
            return "https://github.com/glennrp/\(rawValue)"
        case .mpv:
            return "https://github.com/\(rawValue)-player/\(rawValue)"
        case .srt:
            return "https://github.com/Haivision/\(rawValue)"
        case .smbclient:
            return "https://github.com/samba-team/samba"
        case .nettle:
            return "https://github.com/gnutls/nettle"
        case .gmp:
            return "https://github.com/alisw/GMP"
        default:
            return "https://github.com/\(rawValue)/\(rawValue)"
        }
    }
}

private class BaseBuild {
    static var platforms = PlatformType.allCases
    private let library: Library
    let directoryURL: URL
    init(library: Library) {
        self.library = library
        directoryURL = URL.currentDirectory + "\(library.rawValue)-\(library.version)"
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try! Utility.launch(path: "/usr/bin/git", arguments: ["clone", "--depth", "1", "--branch", library.version, library.url, directoryURL.path])
        }
    }

    func buildALL() throws {
        try? FileManager.default.removeItem(at: URL.currentDirectory + library.rawValue)
        for platform in BaseBuild.platforms {
            for arch in architectures(platform) {
                try build(platform: platform, arch: arch)
            }
        }
        try createXCFramework()
    }

    func architectures(_ platform: PlatformType) -> [ArchType] {
        platform.architectures()
    }

    func build(platform: PlatformType, arch: ArchType) throws {
        let buildURL = scratch(platform: platform, arch: arch)
        try? FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)
        try? _ = Utility.launch(path: "/usr/bin/make", arguments: ["distclean"], currentDirectoryURL: buildURL)
        let environ = environment(platform: platform, arch: arch)
        try configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
        try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "-s"], currentDirectoryURL: buildURL, environment: environ)
        try Utility.launch(path: "/usr/bin/make", arguments: ["-j5", "install", "-s"], currentDirectoryURL: buildURL, environment: environ)
    }

    func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let autogen = directoryURL + "autogen.sh"
        if FileManager.default.fileExists(atPath: autogen.path) {
            var environ = environ
            environ["NOCONFIGURE"] = "1"
            try Utility.launch(executableURL: autogen, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        let configure = directoryURL + "configure"
        var bootstrap = directoryURL + "bootstrap"
        if !FileManager.default.fileExists(atPath: configure.path), FileManager.default.fileExists(atPath: bootstrap.path) {
            try Utility.launch(executableURL: bootstrap, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        bootstrap = directoryURL + ".bootstrap"
        if !FileManager.default.fileExists(atPath: configure.path), FileManager.default.fileExists(atPath: bootstrap.path) {
            try Utility.launch(executableURL: bootstrap, arguments: [], currentDirectoryURL: directoryURL, environment: environ)
        }
        try Utility.launch(executableURL: configure, arguments: arguments(platform: platform, arch: arch), currentDirectoryURL: buildURL, environment: environ)
    }

    private func pkgConfigPath(platform: PlatformType, arch: ArchType) -> String {
        var pkgConfigPath = ""
        for lib in Library.allCases {
            let path = URL.currentDirectory + [lib.rawValue, platform.rawValue, "thin", arch.rawValue]
            if FileManager.default.fileExists(atPath: path.path) {
                pkgConfigPath += "\(path.path)/lib/pkgconfig:"
            }
        }
        return pkgConfigPath
    }

    func environment(platform: PlatformType, arch: ArchType) -> [String: String] {
        ["LC_CTYPE": "C",
         "CC": ccFlags(platform: platform, arch: arch),
         "CFLAGS": cFlags(platform: platform, arch: arch),
         "CXXFLAGS": cFlags(platform: platform, arch: arch),
         "LDFLAGS": ldFlags(platform: platform, arch: arch),
         "PKG_CONFIG_PATH": pkgConfigPath(platform: platform, arch: arch),
         "CMAKE_OSX_ARCHITECTURES": arch.rawValue,
         "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"]
    }

    func ccFlags(platform _: PlatformType, arch _: ArchType) -> String {
        "/usr/bin/clang "
    }

    func cFlags(platform: PlatformType, arch: ArchType) -> String {
        var cflags = "-arch " + arch.rawValue + " " + platform.deploymentTarget(arch)
        if platform == .macos || platform == .maccatalyst {
            cflags += " -fno-common"
        }
        let syslibroot = platform.isysroot()
        cflags += " -isysroot \(syslibroot)"
        if platform == .maccatalyst {
            cflags += " -iframework \(syslibroot)/System/iOSSupport/System/Library/Frameworks"
        }
        if platform == .tvos || platform == .tvsimulator {
            cflags += " -DHAVE_FORK=0"
        }
        return cflags
    }

    func ldFlags(platform: PlatformType, arch: ArchType) -> String {
        cFlags(platform: platform, arch: arch)
    }

    func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        [
            "--prefix=\(thinDir(platform: platform, arch: arch).path)",
        ]
    }

    func createXCFramework() throws {
        var frameworks: [String] = []
        if let platform = BaseBuild.platforms.first {
            if let arch = architectures(platform).first {
                let lib = thinDir(platform: platform, arch: arch) + "lib"
                let fileNames = try FileManager.default.contentsOfDirectory(atPath: lib.path)
                for fileName in fileNames {
                    if fileName.hasPrefix("lib"), fileName.hasSuffix(".a") {
                        frameworks.append("Lib" + fileName.dropFirst(3).dropLast(2))
                    }
                }
            }
        }
        for framework in frameworks {
            var arguments = ["-create-xcframework"]
            for platform in BaseBuild.platforms {
                arguments.append("-framework")
                arguments.append(try createFramework(framework: framework, platform: platform))
            }
            arguments.append("-output")
            let XCFrameworkFile = URL.currentDirectory + ["../Sources", framework + ".xcframework"]
            arguments.append(XCFrameworkFile.path)
            if FileManager.default.fileExists(atPath: XCFrameworkFile.path) {
                try? FileManager.default.removeItem(at: XCFrameworkFile)
            }
            try Utility.launch(path: "/usr/bin/xcodebuild", arguments: arguments)
        }
    }

    private func createFramework(framework: String, platform: PlatformType) throws -> String {
        let frameworkDir = URL.currentDirectory + [library.rawValue, platform.rawValue, "\(framework).framework"]
        try? FileManager.default.removeItem(at: frameworkDir)
        try? FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true, attributes: nil)
        var arguments = ["-create"]
        for arch in architectures(platform) {
            let prefix = thinDir(platform: platform, arch: arch)
            arguments.append((prefix + ["lib", "\(framework).a"]).path)
            var headerURL = prefix + "include" + framework
            if !FileManager.default.fileExists(atPath: headerURL.path) {
                headerURL = prefix + "include"
            }
            try? FileManager.default.copyItem(at: headerURL, to: frameworkDir + "Headers")
        }
        arguments.append("-output")
        arguments.append((frameworkDir + framework).path)
        try Utility.launch(path: "/usr/bin/lipo", arguments: arguments)
        try? FileManager.default.createDirectory(at: frameworkDir + "Modules", withIntermediateDirectories: true, attributes: nil)
        var modulemap = """
        framework module \(framework) [system] {
            umbrella "."

        """
        frameworkExcludeHeaders(framework).forEach { header in
            modulemap += """
                exclude header "\(header).h"

            """
        }
        modulemap += """
            export *
        }
        """
        FileManager.default.createFile(atPath: frameworkDir.path + "/Modules/module.modulemap", contents: modulemap.data(using: .utf8), attributes: nil)
        createPlist(path: frameworkDir.path + "/Info.plist", name: framework, minVersion: platform.minVersion, platform: platform.sdk())
        return frameworkDir.path
    }

    func thinDir(platform: PlatformType, arch: ArchType) -> URL {
        URL.currentDirectory + [library.rawValue, platform.rawValue, "thin", arch.rawValue]
    }

    func scratch(platform: PlatformType, arch: ArchType) -> URL {
        URL.currentDirectory + [library.rawValue, platform.rawValue, "scratch", arch.rawValue]
    }

    func frameworkExcludeHeaders(_: String) -> [String] {
        []
    }

    private func createPlist(path: String, name: String, minVersion: String, platform: String) {
        let identifier = "com.kintan.ksplayer." + name
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>\(name)</string>
        <key>CFBundleIdentifier</key>
        <string>\(identifier)</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>\(name)</string>
        <key>CFBundlePackageType</key>
        <string>FMWK</string>
        <key>CFBundleShortVersionString</key>
        <string>87.88.520</string>
        <key>CFBundleVersion</key>
        <string>87.88.520</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>MinimumOSVersion</key>
        <string>\(minVersion)</string>
        <key>CFBundleSupportedPlatforms</key>
        <array>
        <string>\(platform)</string>
        </array>
        <key>NSPrincipalClass</key>
        <string></string>
        </dict>
        </plist>
        """
        FileManager.default.createFile(atPath: path, contents: content.data(using: .utf8), attributes: nil)
    }
}

private class BuildFFMPEG: BaseBuild {
    private let isDebug: Bool
    init(arguments: [String]) {
        isDebug = arguments.firstIndex(of: "enable-debug") != nil
        super.init(library: .FFmpeg)
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        try super.build(platform: platform, arch: arch)
        let prefix = thinDir(platform: platform, arch: arch)
        let buildDir = scratch(platform: platform, arch: arch)
        let lldbFile = URL.currentDirectory + "LLDBInitFile"
        if let data = FileManager.default.contents(atPath: lldbFile.path), var str = String(data: data, encoding: .utf8) {
            str.append("settings \(str.count == 0 ? "set" : "append") target.source-map \((buildDir + "src").path) \(directoryURL.path)\n")
            try str.write(toFile: lldbFile.path, atomically: true, encoding: .utf8)
        }
        if platform == .macos, arch.executable() {
            try replaceBin(prefix: prefix, item: "ffmpeg")
            try replaceBin(prefix: prefix, item: "ffplay")
            try replaceBin(prefix: prefix, item: "ffprobe")
        }
    }

    override func environment(platform: PlatformType, arch: ArchType) -> [String: String] {
        var environ = super.environment(platform: platform, arch: arch)
        environ["CPPFLAGS"] = cFlags(platform: platform, arch: arch)
        return environ
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        var arguments = super.arguments(platform: platform, arch: arch)
        arguments += ffmpegConfiguers
        arguments.append("--target-os=darwin")
        arguments.append("--arch=\(arch.arch())")
        arguments.append(arch.cpu())
        if isDebug {
            arguments.append("--enable-debug")
            arguments.append("--disable-stripping")
            arguments.append("--disable-optimizations")
        } else {
            arguments.append("--disable-debug")
            arguments.append("--enable-stripping")
            arguments.append("--enable-optimizations")
        }
        /**
         aacpsdsp.o), building for Mac Catalyst, but linking in object file built for
         x86_64 binaries are built without ASM support, since ASM for x86_64 is actually x86 and that confuses `xcodebuild -create-xcframework` https://stackoverflow.com/questions/58796267/building-for-macos-but-linking-in-object-file-built-for-free-standing/59103419#59103419
         */
        if platform == .maccatalyst || arch == .x86_64 {
            arguments.append("--disable-neon")
            arguments.append("--disable-asm")
        } else {
            arguments.append("--enable-neon")
            arguments.append("--enable-asm")
        }
        if platform == .macos, arch.executable() {
            arguments.append("--enable-ffplay")
            arguments.append("--enable-sdl2")
            arguments.append("--enable-encoder=aac")
            arguments.append("--enable-encoder=movtext")
            arguments.append("--enable-encoder=mpeg4")
            arguments.append("--enable-decoder=rawvideo")
            arguments.append("--enable-filter=color")
            arguments.append("--enable-filter=lut")
            arguments.append("--enable-filter=negate")
            arguments.append("--enable-filter=testsrc")
            arguments.append("--disable-avdevice")
            //            arguments.append("--enable-avdevice")
            //            arguments.append("--enable-indev=lavfi")
        } else {
            arguments.append("--disable-avdevice")
            arguments.append("--disable-programs")
        }
        //        if platform == .isimulator || platform == .tvsimulator {
        //            arguments.append("--assert-level=1")
        //        }
        for library in [Library.openssl, .libass, .fribidi, .freetype, .srt, .smbclient] {
            let path = URL.currentDirectory + [library.rawValue, platform.rawValue, "thin", arch.rawValue]
            if FileManager.default.fileExists(atPath: path.path) {
                let libraryName = [.openssl, .libass].contains(library) ? library.rawValue : "lib" + library.rawValue
                arguments.append("--enable-\(libraryName)")
                if library == .srt {
                    arguments.append("--enable-protocol=\(libraryName)")
                }
            }
        }
        return arguments
    }

    private func replaceBin(prefix: URL, item: String) throws {
        if FileManager.default.fileExists(atPath: (prefix + ["bin", item]).path) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/usr/local/bin/\(item)"))
            try? FileManager.default.copyItem(at: prefix + ["bin", item], to: URL(fileURLWithPath: "/usr/local/bin/\(item)"))
        }
    }

//    override func createXCFramework() throws {
//        try super.createXCFramework()
//        makeFFmpegSourece()
//    }

    private func makeFFmpegSourece() throws {
        guard let platform = BaseBuild.platforms.first, let arch = architectures(platform).first else {
            return
        }
        let target = URL.currentDirectory + ["../Sources", "FFmpeg"]
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: nil)
        let thin = thinDir(platform: platform, arch: arch)
        try? FileManager.default.copyItem(at: thin + "include", to: target + "include")
        let scratchURL = scratch(platform: platform, arch: arch)
        try? FileManager.default.createDirectory(at: target + "include", withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.copyItem(at: scratchURL + "config.h", to: target + "include" + "config.h")
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: scratchURL.path)
        for fileName in fileNames where fileName.hasPrefix("lib") {
            var url = scratchURL + fileName
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                // copy .c
                if let subpaths = FileManager.default.enumerator(atPath: url.path) {
                    let dstDir = target + fileName
                    while let subpath = subpaths.nextObject() as? String {
                        if subpath.hasSuffix(".c") {
                            let srcURL = url + subpath
                            let dstURL = target + "include" + fileName + subpath
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        } else if subpath.hasSuffix(".o") {
                            let subpath = subpath.replacingOccurrences(of: ".o", with: ".c")
                            let srcURL = scratchURL + "src" + fileName + subpath
                            let dstURL = dstDir + subpath
                            let dstURLDir = dstURL.deletingLastPathComponent()
                            if !FileManager.default.fileExists(atPath: dstURLDir.path) {
                                try? FileManager.default.createDirectory(at: dstURLDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        }
                    }
                }
                url = scratchURL + "src" + fileName
                // copy .h
                try? FileManager.default.copyItem(at: scratchURL + "src" + "compat", to: target + "compat")
                if let subpaths = FileManager.default.enumerator(atPath: url.path) {
                    let dstDir = target + "include" + fileName
                    while let subpath = subpaths.nextObject() as? String {
                        if subpath.hasSuffix(".h") || subpath.hasSuffix("_template.c") {
                            let srcURL = url + subpath
                            let dstURL = dstDir + subpath
                            let dstURLDir = dstURL.deletingLastPathComponent()
                            if !FileManager.default.fileExists(atPath: dstURLDir.path) {
                                try? FileManager.default.createDirectory(at: dstURLDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                        }
                    }
                }
            }
        }
    }

    override func buildALL() throws {
        if Utility.shell("which nasm") == nil {
            Utility.shell("brew install nasm")
        }
        if Utility.shell("which sdl2-config") == nil {
            Utility.shell("brew install sdl2")
        }
        let lldbFile = URL.currentDirectory + "LLDBInitFile"
        try? FileManager.default.removeItem(at: lldbFile)
        FileManager.default.createFile(atPath: lldbFile.path, contents: nil, attributes: nil)
        let path = directoryURL + "libavcodec/videotoolbox.c"
        if let data = FileManager.default.contents(atPath: path.path), var str = String(data: data, encoding: .utf8) {
            str = str.replacingOccurrences(of: "kCVPixelBufferOpenGLESCompatibilityKey", with: "kCVPixelBufferMetalCompatibilityKey")
            str = str.replacingOccurrences(of: "kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey", with: "kCVPixelBufferMetalCompatibilityKey")
            try str.write(toFile: path.path, atomically: true, encoding: .utf8)
        }
        try super.buildALL()
    }

    override func frameworkExcludeHeaders(_ framework: String) -> [String] {
        if framework == "Libavcodec" {
            return ["xvmc", "vdpau", "qsv", "dxva2", "d3d11va"]
        } else if framework == "Libavutil" {
            return ["hwcontext_vulkan", "hwcontext_vdpau", "hwcontext_vaapi", "hwcontext_qsv", "hwcontext_opencl", "hwcontext_dxva2", "hwcontext_d3d11va", "hwcontext_cuda"]
        } else {
            return super.frameworkExcludeHeaders(framework)
        }
    }

    private let ffmpegConfiguers = [
        // Configuration options:
        "--disable-armv5te", "--disable-armv6", "--disable-armv6t2", "--disable-bsfs",
        "--disable-bzlib", "--disable-gray", "--disable-iconv", "--disable-linux-perf",
        "--disable-xlib", "--disable-swscale-alpha", "--disable-symver", "--disable-small",
        "--enable-cross-compile", "--enable-gpl", "--enable-libxml2", "--enable-nonfree",
        "--enable-runtime-cpudetect", "--enable-thumb", "--enable-version3", "--pkg-config-flags=--static",
        "--enable-static", "--disable-shared",
        // Documentation options:
        "--disable-doc", "--disable-htmlpages", "--disable-manpages", "--disable-podpages", "--disable-txtpages",
        // Component options:
        "--enable-avcodec", "--enable-avformat", "--enable-avutil", "--enable-network", "--enable-swresample", "--enable-swscale",
        "--disable-devices", "--disable-outdevs", "--disable-indevs", "--disable-postproc",
        // ,"--disable-pthreads"
        // ,"--disable-w32threads"
        // ,"--disable-os2threads"
        // ,"--disable-dct"
        // ,"--disable-dwt"
        // ,"--disable-lsp"
        // ,"--disable-lzo"
        // ,"--disable-mdct"
        // ,"--disable-rdft"
        // ,"--disable-fft"
        // Hardware accelerators:
        "--disable-d3d11va", "--disable-dxva2", "--disable-vaapi", "--disable-vdpau",
        "--enable-videotoolbox", "--enable-audiotoolbox",
        // Individual component options:
        // ,"--disable-everything"
        // If all encoders are used, the avcodec will reach 40MB, and if specified, it only needs 20MB.
        // ./configure --list-encoders
        "--disable-encoders",
        // video
        "--enable-encoder=dca", "--enable-encoder=flv", "--enable-encoder=h263*", "--enable-encoder=h264",
        "--enable-encoder=hevc*", "--enable-encoder=mjpeg*", "--enable-encoder=mpeg1video", "--enable-encoder=mpeg2video",
        "--enable-encoder=mpeg4*", "--enable-encoder=wmv1", "--enable-encoder=wmv2", "--enable-encoder=vp6*",
        "--enable-encoder=libvpx_vp8", "--enable-encoder=libvpx_vp9",
        // audio
        "--enable-encoder=aac*", "--enable-encoder=ac3*", "--enable-encoder=alac*", "--enable-encoder=dca",
        "--enable-encoder=eac3", "--enable-encoder=flac", "--enable-encoder=mp2", "--enable-encoder=libmp3lame",
        "--enable-encoder=mp3_mf", "--enable-encoder=libopus", "--enable-encoder=pcm*", "--enable-encoder=truehd",
        "--enable-encoder=vorbis", "--enable-encoder=wma*",
        // subtitle
        "--enable-encoder=ass", "--enable-encoder=dvbsub", "--enable-encoder=dvdsub", "--enable-encoder=",
        "--enable-encoder=movtext", "--enable-encoder=srt", "--enable-encoder=ssa", "--enable-encoder=subrip",
        "--enable-encoder=webvtt",
        
        // ./configure --list-decoders
        "--disable-decoders",
        // video
        "--enable-decoder=av1", "--enable-decoder=dca", "--enable-decoder=flv", "--enable-decoder=h263",
        "--enable-decoder=h263i", "--enable-decoder=h263p", "--enable-decoder=h264", "--enable-decoder=hevc",
        "--enable-decoder=mjpeg", "--enable-decoder=mjpegb", "--enable-decoder=mpeg1video", "--enable-decoder=mpeg2video",
        "--enable-decoder=mpeg4", "--enable-decoder=mpegvideo", "--enable-decoder=rv30", "--enable-decoder=rv40",
        "--enable-decoder=tscc", "--enable-decoder=wmv1", "--enable-decoder=wmv2", "--enable-decoder=wmv3",
        "--enable-decoder=vc1", "--enable-decoder=vp6", "--enable-decoder=vp6a", "--enable-decoder=vp6f",
        "--enable-decoder=vp7", "--enable-decoder=vp8", "--enable-decoder=vp9",
        // audio
        "--enable-decoder=aac*", "--enable-decoder=ac3*", "--enable-decoder=alac*",
        "--enable-decoder=amr*", "--enable-decoder=ape", "--enable-decoder=cook",
        "--enable-decoder=dca", "--enable-decoder=dolby_e", "--enable-decoder=eac3*", "--enable-decoder=flac",
        "--enable-decoder=mp1*", "--enable-decoder=mp2*", "--enable-decoder=mp3*", "--enable-decoder=opus",
        "--enable-decoder=pcm*", "--enable-decoder=truehd", "--enable-decoder=vorbis", "--enable-decoder=wma*",
        // subtitle
        "--enable-decoder=ass", "--enable-decoder=ccaption", "--enable-decoder=dvbsub", "--enable-decoder=dvdsub", "--enable-decoder=movtext",
        "--enable-decoder=pgssub", "--enable-decoder=srt", "--enable-decoder=ssa", "--enable-decoder=subrip",
        "--enable-decoder=webvtt",
        // ./configure --list-muxers
        "--disable-muxers",
        "--enable-muxer=mp4",
        "--enable-muxer=webm",
        "--enable-muxer=ac3", "--enable-muxer=aiff", "--enable-muxer=amr",
        "--enable-muxer=asf", "--enable-muxer=ass", "--enable-muxer=avi", "--enable-muxer=caf",
        "--enable-muxer=dash", "--enable-muxer=data", "--enable-muxer=eac3",
        "--enable-muxer=flac", "--enable-muxer=flv", "--enable-muxer=h264", "--enable-muxer=hevc",
        "--enable-muxer=hls", "--enable-muxer=m4v",
        "--enable-muxer=matroska", "--enable-muxer=mov", "--enable-muxer=mp3", "--enable-muxer=mpeg*",
        "--enable-muxer=ogg", "--enable-muxer=rm", "--enable-muxer=rstp", "--enable-muxer=rst",
        "--enable-muxer=vc1", "--enable-muxer=wav", "--enable-muxer=webm_dash_manifest",
        "--enable-muxer=mpegts",
        // ./configure --list-demuxers
        // With all demuxers, avformat will reach 8MB, and if specified, it only needs 4MB.
        "--disable-demuxers",
        "--enable-demuxer=aac",
        "--enable-demuxer=ape",
        "--enable-demuxer=concat",
        "--enable-demuxer=live_flv",
        "--enable-demuxer=loas",
        "--enable-demuxer=ac3", "--enable-demuxer=aiff", "--enable-demuxer=amr",
        "--enable-demuxer=asf", "--enable-demuxer=ass", "--enable-demuxer=avi", "--enable-demuxer=caf",
        "--enable-demuxer=dash", "--enable-demuxer=data", "--enable-demuxer=eac3",
        "--enable-demuxer=flac", "--enable-demuxer=flv", "--enable-demuxer=h264", "--enable-demuxer=hevc",
        "--enable-demuxer=hls", "--enable-demuxer=m4v",
        "--enable-demuxer=matroska", "--enable-demuxer=mov", "--enable-demuxer=mp3", "--enable-demuxer=mpeg*",
        "--enable-demuxer=ogg", "--enable-demuxer=rm", "--enable-demuxer=rtsp", "--enable-demuxer=srt",
        "--enable-demuxer=vc1", "--enable-demuxer=wav", "--enable-demuxer=webm_dash_manifest",
        "--enable-demuxer=mpegts",
        // ./configure --list-protocols
        "--enable-protocols",
        "--disable-protocol=bluray", "--disable-protocol=ffrtmpcrypt", "--disable-protocol=gopher", "--disable-protocol=icecast",
        "--disable-protocol=librtmp*", "--disable-protocol=libssh", "--disable-protocol=md5", "--disable-protocol=mmsh",
        "--disable-protocol=mmst", "--disable-protocol=sctp", "--disable-protocol=subfile", "--disable-protocol=unix",
        // filters
        "--disable-filters",
        "--enable-filter=aformat", "--enable-filter=amix", "--enable-filter=anull", "--enable-filter=aresample",
        "--enable-filter=areverse", "--enable-filter=asetrate", "--enable-filter=atempo", "--enable-filter=atrim",
        "--enable-filter=bwdif", "--enable-filter=estdif", "--enable-filter=format", "--enable-filter=fps",
        "--enable-filter=hflip", "--enable-filter=hwdownload", "--enable-filter=hwmap", "--enable-filter=hwupload",
        "--enable-filter=idet", "--enable-filter=null",
        "--enable-filter=overlay", "--enable-filter=palettegen", "--enable-filter=paletteuse", "--enable-filter=pan",
        "--enable-filter=rotate", "--enable-filter=scale", "--enable-filter=setpts", "--enable-filter=transpose",
        "--enable-filter=trim", "--enable-filter=vflip", "--enable-filter=volume", "--enable-filter=w3fdif",
        "--enable-filter=yadif", "--enable-filter=yadif_videotoolbox",
    ]
}

private class BuildOpenSSL: BaseBuild {
    init() {
        super.init(library: .openssl)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                arch == .x86_64 ? "darwin64-x86_64" : arch == .arm64e ? "iphoneos-cross" : "darwin64-arm64",
                "no-async", "no-shared", "no-dso", "no-engine", "no-tests",
            ]
    }
}

private class BuildSmbclient: BaseBuild {
    init() {
        super.init(library: .smbclient)
    }

    override func scratch(platform _: PlatformType, arch _: ArchType) -> URL {
        directoryURL
    }
}

private class BuildGmp: BaseBuild {
    init() {
        super.init(library: .gmp)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--disable-maintainer-mode",
                "--disable-assembly",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildNettle: BaseBuild {
    init() {
        super.init(library: .nettle)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--disable-mini-gmp",
                "--disable-assembler",
                "--disable-openssl",
                "--disable-gcov",
                "--disable-documentation",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildGnutls: BaseBuild {
    init() {
        super.init(library: .gnutls)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-included-libtasn1",
                "--with-included-unistring",
                "--without-idn",
                "--without-p11-kit",
                "--enable-hardware-acceleration",
                "--disable-openssl-compatibility",
                "--disable-code-coverage",
                "--disable-doc",
                "--disable-manpages",
                "--disable-guile",
                "--disable-tests",
                "--disable-tools",
                "--disable-maintainer-mode",
                "--disable-full-test-suite",
                "--disable-debug",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildSRT: BaseBuild {
    init() {
        super.init(library: .srt)
    }

    override func buildALL() throws {
        if Utility.shell("which cmake") == nil {
            Utility.shell("brew install cmake")
        }
        try super.buildALL()
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        let thinDirPath = thinDir(platform: platform, arch: arch).path

        let arguments = [
            (directoryURL + "CMakeLists.txt").path,
            "-Wno-dev",
            "-DUSE_ENCLIB=openssl",
            "-DCMAKE_VERBOSE_MAKEFILE=0",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_PREFIX_PATH=\(thinDirPath)",
            "-DCMAKE_INSTALL_PREFIX=\(thinDirPath)",
            "-DENABLE_STDCXX_SYNC=1",
            "-DENABLE_CXX11=1",
            "-DUSE_OPENSSL_PC=1",
            "-DENABLE_DEBUG=0",
            "-DENABLE_LOGGING=0",
            "-DENABLE_HEAVY_LOGGING=0",
            "-DENABLE_APPS=0",
            "-DENABLE_SHARED=0",
            platform == .maccatalyst ? "-DENABLE_MONOTONIC_CLOCK=0" : "-DENABLE_MONOTONIC_CLOCK=1",
        ]
        try Utility.launch(path: "/usr/local/bin/cmake", arguments: arguments, currentDirectoryURL: buildURL, environment: environ)
    }
}

private class BuildFribidi: BaseBuild {
    init() {
        super.init(library: .fribidi)
    }

    override func configure(buildURL: URL, environ: [String: String], platform: PlatformType, arch: ArchType) throws {
        try super.configure(buildURL: buildURL, environ: environ, platform: platform, arch: arch)
        let makefile = buildURL + "Makefile"
        // DISABLE BUILDING OF doc FOLDER (doc depends on c2man which is not available on all platforms)
        if let data = FileManager.default.contents(atPath: makefile.path), var str = String(data: data, encoding: .utf8) {
            str = str.replacingOccurrences(of: " doc ", with: " ")
            try? str.write(toFile: makefile.path, atomically: true, encoding: .utf8)
        }
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--disable-deprecated",
                "--disable-debug",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildHarfbuzz: BaseBuild {
    init() {
        super.init(library: .harfbuzz)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-glib=no",
                "--with-freetype=no",
                "--with-directwrite=no",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildFreetype: BaseBuild {
    init() {
        super.init(library: .freetype)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--with-zlib",
                "--without-harfbuzz",
                "--without-bzip2",
                "--without-fsref",
                "--without-quickdraw-toolbox",
                "--without-quickdraw-carbon",
                "--without-ats",
                "--disable-mmap",
                "--with-png=no",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildPng: BaseBuild {
    init() {
        super.init(library: .libpng)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        let asmOptions = arch == .x86_64 ? "--enable-intel-sse=yes" : "--enable-arm-neon=yes"
        return super.arguments(platform: platform, arch: arch) +
            [
                asmOptions,
                "--disable-unversioned-libpng-pc",
                "--disable-unversioned-libpng-config",
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildASS: BaseBuild {
    init() {
        super.init(library: .libass)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        // todo
//        let asmOptions = platform == .maccatalyst || arch == .x86_64 ? "--disable-asm" : "--enable-asm"
        let asmOptions = "--disable-asm"
        return super.arguments(platform: platform, arch: arch) +
            [
                "--disable-libtool-lock",
                "--disable-fontconfig",
                "--disable-require-system-font-provider",
                "--disable-test",
                "--disable-profile",
                "--disable-coretext",
                asmOptions,
                "--with-pic",
                "--enable-static",
                "--disable-shared",
                "--disable-fast-install",
                "--disable-dependency-tracking",
                "--host=\(platform.host(arch: arch))",
                "--with-sysroot=\(platform.isysroot())",
            ]
    }
}

private class BuildMPV: BaseBuild {
    init() {
        super.init(library: .mpv)
    }

    override func buildALL() throws {
        let path = directoryURL + "wscript_build.py"
        if let data = FileManager.default.contents(atPath: path.path), var str = String(data: data, encoding: .utf8) {
            str = str.replacingOccurrences(of:
                """
                "osdep/subprocess-posix.c",            "posix"
                """, with:
                """
                "osdep/subprocess-posix.c",            "posix && !tvos"
                """)
            try str.write(toFile: path.path, atomically: true, encoding: .utf8)
        }
        try super.buildALL()
    }

    override func build(platform: PlatformType, arch: ArchType) throws {
        let url = scratch(platform: platform, arch: arch)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        let environ = environment(platform: platform, arch: arch)
        try Utility.launch(executableURL: directoryURL + "bootstrap.py", arguments: [], currentDirectoryURL: directoryURL)
        try Utility.launch(path: "/usr/bin/python3", arguments: ["./waf", "distclean"], currentDirectoryURL: directoryURL, environment: environ)
        try Utility.launch(path: "/usr/bin/python3", arguments: ["./waf", "configure"] + arguments(platform: platform, arch: arch), currentDirectoryURL: directoryURL, environment: environ)
        try Utility.launch(path: "/usr/bin/python3", arguments: ["./waf", "build"], currentDirectoryURL: directoryURL, environment: environ)
        try Utility.launch(path: "/usr/bin/python3", arguments: ["./waf", "install"], currentDirectoryURL: directoryURL, environment: environ)
    }

    override func arguments(platform: PlatformType, arch: ArchType) -> [String] {
        super.arguments(platform: platform, arch: arch) +
            [
                "--disable-cplayer",
                "--disable-lcms2",
                "--disable-lua",
                "--disable-rubberband",
                "--disable-zimg",
                "--disable-javascript",
                "--disable-jpeg",
                "--disable-swift",
                "--disable-vapoursynth",
                "--enable-lgpl",
                "--enable-libmpv-static",
                platform == .macos ? "--enable-videotoolbox-gl" : (platform == .maccatalyst ? "--enable-gl" : "--enable-ios-gl"),
            ]
    }

//    override func architectures(_ platform: PlatformType) -> [ArchType] {
//        if platform == .macos {
//            return [.x86_64]
//        } else {
//            return super.architectures(platform)
//        }
//    }
}

private enum PlatformType: String, CaseIterable {
    case ios, isimulator, tvos, tvsimulator, macos, maccatalyst
    var minVersion: String {
        switch self {
        case .ios, .isimulator:
            return "13.0"
        case .tvos, .tvsimulator:
            return "13.0"
        case .macos:
            return "10.15"
        case .maccatalyst:
            return "13.0"
        }
    }

    func architectures() -> [ArchType] {
        switch self {
        case .ios:
            return [.arm64, .arm64e]
        case .tvos:
            return [.arm64]
        case .isimulator, .tvsimulator:
            return [.arm64, .x86_64]
        case .macos:
            #if arch(x86_64)
            return [.x86_64, .arm64]
            #else
            return [.arm64, .x86_64]
            #endif
        case .maccatalyst:
            return [.arm64, .x86_64]
        }
    }

    func deploymentTarget(_ arch: ArchType) -> String {
        switch self {
        case .ios:
            return "-mios-version-min=\(minVersion)"
        case .isimulator:
            return "-mios-simulator-version-min=\(minVersion)"
        case .tvos:
            return "-mtvos-version-min=\(minVersion)"
        case .tvsimulator:
            return "-mtvos-simulator-version-min=\(minVersion)"
        case .macos:
            return "-mmacosx-version-min=\(minVersion)"
        case .maccatalyst:
            return arch == .x86_64 ? "-target x86_64-apple-ios-macabi" : "-target arm64-apple-ios-macabi"
        }
    }

    func sdk() -> String {
        switch self {
        case .ios:
            return "iPhoneOS"
        case .isimulator:
            return "iPhoneSimulator"
        case .tvos:
            return "AppleTVOS"
        case .tvsimulator:
            return "AppleTVSimulator"
        case .macos:
            return "MacOSX"
        case .maccatalyst:
            return "MacOSX"
        }
    }

    func isysroot() -> String {
        try! Utility.launch(path: "/usr/bin/xcrun", arguments: ["--sdk", sdk().lowercased(), "--show-sdk-path"], isOutput: true)
    }

    func host(arch: ArchType) -> String {
        switch self {
        case .ios, .isimulator, .maccatalyst:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-ios-darwin"
        case .tvos, .tvsimulator:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-tvos-darwin"
        case .macos:
            return "\(arch == .x86_64 ? "x86_64" : "arm64")-apple-darwin"
        }
    }
}

enum ArchType: String, CaseIterable {
    // swiftlint:disable identifier_name
    case arm64, x86_64, arm64e
    // swiftlint:enable identifier_name
    func executable() -> Bool {
        guard let architecture = Bundle.main.executableArchitectures?.first?.intValue else {
            return false
        }
        // NSBundleExecutableArchitectureARM64
        if architecture == 0x0100_000C, self == .arm64 {
            return true
        } else if architecture == NSBundleExecutableArchitectureX86_64, self == .x86_64 {
            return true
        }
        return false
    }

    func arch() -> String {
        switch self {
        case .arm64, .arm64e:
            return "aarch64"
        case .x86_64:
            return "x86_64"
        }
    }

    func cpu() -> String {
        switch self {
        case .arm64:
            return "--cpu=armv8"
        case .x86_64:
            return "--cpu=x86_64"
        case .arm64e:
            return "--cpu=armv8.3-a"
        }
    }
}

enum Utility {
    @discardableResult
    static func shell(_ command: String, isOutput _: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) -> String? {
        do {
            return try launch(executableURL: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", command], currentDirectoryURL: currentDirectoryURL, environment: environment)
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    static func launch(path: String, arguments: [String], isOutput: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) throws -> String {
        try launch(executableURL: URL(fileURLWithPath: path), arguments: arguments, isOutput: isOutput, currentDirectoryURL: currentDirectoryURL, environment: environment)
    }

    @discardableResult
    static func launch(executableURL: URL, arguments: [String], isOutput: Bool = false, currentDirectoryURL: URL? = nil, environment: [String: String] = [:]) throws -> String {
        #if os(macOS)
        let task = Process()
        task.environment = environment
        var standardOutput: FileHandle?
        if isOutput {
            let pipe = Pipe()
            task.standardOutput = pipe
            standardOutput = pipe.fileHandleForReading
        } else if var logURL = currentDirectoryURL {
            logURL = logURL.appendingPathExtension("log")
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let standardOutput = try FileHandle(forWritingTo: logURL)
            if #available(macOS 10.15.4, *) {
                try standardOutput.seekToEnd()
            }
            task.standardOutput = standardOutput
        }
        task.arguments = arguments
        var log = executableURL.path + " " + arguments.joined(separator: " ") + " environment: " + environment.description
        if let currentDirectoryURL {
            log += " url: \(currentDirectoryURL)"
        }
        print(log)
        task.currentDirectoryURL = currentDirectoryURL
        task.executableURL = executableURL
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            if isOutput, let standardOutput {
                let data = standardOutput.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
                print(result)
                return result
            } else {
                return ""
            }
        } else {
            throw NSError(domain: "fail", code: Int(task.terminationStatus))
        }
        #else
        return ""
        #endif
    }
}

extension URL {
    static var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func + (left: URL, right: String) -> URL {
        var url = left
        url.appendPathComponent(right)
        return url
    }

    static func + (left: URL, right: [String]) -> URL {
        var url = left
        right.forEach {
            url.appendPathComponent($0)
        }
        return url
    }
}

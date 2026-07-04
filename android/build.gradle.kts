import com.android.build.api.dsl.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            if (namespace == null) {
                namespace = "autogen.${project.name.replace('-', '_')}"
            }
            if (project.name == "flutter_bluetooth_serial") {
                compileSdk = 35
            }
        }
    }
}

subprojects {
    if (name == "flutter_bluetooth_serial") {
        afterEvaluate {
            extensions.configure<LibraryExtension>("android") {
                compileSdk = 35
            }
        }

        val buildGradle = layout.projectDirectory.file("build.gradle").asFile
        if (buildGradle.exists()) {
            var gradleContent = buildGradle.readText()
            val patchedGradle = gradleContent
                .replace("compileSdkVersion 30", "compileSdkVersion 35")
                .replace(
                    "android {",
                    "android {\n    namespace 'io.github.edufolly.flutterbluetoothserial'"
                )
            if (patchedGradle != gradleContent) {
                buildGradle.writeText(patchedGradle)
            }
        }

        val manifestFile = layout.projectDirectory.file("src/main/AndroidManifest.xml").asFile
        if (manifestFile.exists()) {
            val content = manifestFile.readText()
            val patched = content.replace(Regex("""\s+package="[^"]+""""), "")
            if (patched != content) {
                manifestFile.writeText(patched)
            }
        }

        val connectionFile = layout.projectDirectory.file(
            "src/main/java/io/github/edufolly/flutterbluetoothserial/BluetoothConnection.java"
        ).asFile
        if (connectionFile.exists()) {
            val content = connectionFile.readText()
            val target = """
        BluetoothSocket socket = device.createRfcommSocketToServiceRecord(uuid); // @TODO . introduce ConnectionMethod
        if (socket == null) {
            throw new IOException("socket connection not established");
        }

        // Cancel discovery, even though we didn't start it
        bluetoothAdapter.cancelDiscovery();

        socket.connect();

        connectionThread = new ConnectionThread(socket);
        connectionThread.start();
""".trimIndent()
            val replacement = """
        BluetoothSocket socket = null;
        IOException lastException = null;

        try {
            socket = device.createRfcommSocketToServiceRecord(uuid); // @TODO . introduce ConnectionMethod
            if (socket != null) {
                bluetoothAdapter.cancelDiscovery();
                socket.connect();
            }
        } catch (IOException ex) {
            lastException = ex;
            try {
                if (socket != null) {
                    socket.close();
                }
            } catch (Exception ignored) {}

            socket = device.createInsecureRfcommSocketToServiceRecord(uuid);
            if (socket != null) {
                bluetoothAdapter.cancelDiscovery();
                socket.connect();
            }
        }

        if (socket == null || !socket.isConnected()) {
            if (lastException != null) {
                throw lastException;
            }
            throw new IOException("socket connection not established");
        }

        connectionThread = new ConnectionThread(socket);
        connectionThread.start();
""".trimIndent()

            if (content.contains(target)) {
                connectionFile.writeText(content.replace(target, replacement))
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

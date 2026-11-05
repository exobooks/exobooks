(ns build
  "`clojure -T:build uber` -> target/exobooks.jar, AOT-compiled, runnable with
  `java -jar` alone: the manifest carries Enable-Native-Access, which the FFM calls need."
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/exobooks.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn clean [_] (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
  (b/compile-clj {:basis        @basis
                  :class-dir    class-dir
                  ;; exobooks.hello requires sqlite4clj inside -main (so it can check the Java
                  ;; version first), which hides it from the compiler: name it here, or the jar
                  ;; compiles it from source at every start.
                  :ns-compile   '[exobooks.hello sqlite4clj.core]
                  ;; sqlite4clj loads libsqlite3 when it loads, so the compiling JVM needs this too.
                  :java-opts    ["--enable-native-access=ALL-UNNAMED"]
                  :compile-opts {:direct-linking true}})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis     @basis
           :main      'exobooks.hello
           :manifest  {"Enable-Native-Access" "ALL-UNNAMED"}}))

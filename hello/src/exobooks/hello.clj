(ns exobooks.hello
  "Prints hello world, then checks what the real exobooks will need from the machine: the
  supported Java version, and loading the bundled SQLite library through the FFM API
  (java.lang.foreign). The output says in words what happened: the last line starts with OK
  or with FAILED, and a FAILED line says what failed and why. Nobody should need the exit
  code (0 for OK, 1 otherwise).

  sqlite4clj is required inside -main, not in the ns form, so that another Java gets the
  message below instead of an error from deep inside a missing API."
  (:require [clojure.string :as str])
  (:gen-class))

(defmacro ^:private supported-java
  "The one Java version exobooks supports: the number in .java-version at the top of the
  repository, read when this namespace is compiled, so that it is written down in one
  place. The path is relative to this directory's parent, where builds run from."
  []
  (let [text (str/trim (slurp "../.java-version"))]
    (or (parse-long text)
        (throw (ex-info (str ".java-version should hold one whole number, such as 26; it holds: " (pr-str text)) {})))))

;; The only version asked for or accepted. The SQLite part of this program does run on some
;; others (24, 25 and 27 when this was written; on 22 and 23 babashka/ffi dies with a
;; NoSuchMethodError, since the Class-File API it builds its bindings with is final in 24),
;; but nothing else of exobooks is tested on them, so they are refused.
(def required-java (supported-java))

(defn- sqlite-check
  "Opens an in-memory database, returns [sqlite-version sum-of-1-to-10]."
  []
  (let [init-db! (requiring-resolve 'sqlite4clj.core/init-db!)
        q        (requiring-resolve 'sqlite4clj.core/q)
        db       (init-db! ":memory:" {:pool-size 1})]
    (q (:writer db) ["CREATE TABLE t (n INTEGER)"])
    (doseq [n (range 1 11)] (q (:writer db) ["INSERT INTO t VALUES (?)" n]))
    [(first (q (:reader db) ["SELECT sqlite_version()"]))
     (first (q (:reader db) ["SELECT sum(n) FROM t"]))]))

(defn -main [& _]
  (println "hello world")
  (println "java:   " (System/getProperty "java.version") (System/getProperty "java.vendor") "at" (System/getProperty "java.home"))
  (println "os:     " (System/getProperty "os.name") (System/getProperty "os.version") (System/getProperty "os.arch"))
  (println "heap:   " (quot (.maxMemory (Runtime/getRuntime)) (* 1024 1024)) "MB max")
  (let [feature (.feature (Runtime/version))]
    (when (not= feature required-java)
      (println (str "FAILED: exobooks needs Java " required-java "; this is Java " feature
                    ". Install Java " required-java " (see the README) and run again."))
      (System/exit 1)))
  (let [[version sum] (try
                        (sqlite-check)
                        (catch Throwable t
                          (println (str "FAILED: Java " required-java " is here, but the bundled SQLite"
                                        " could not be loaded or run."))
                          (println "Cause:" (str (last (take-while some? (iterate ex-cause t)))))
                          (println "Full error:")
                          (.printStackTrace t (java.io.PrintWriter. *out* true))
                          (System/exit 1)))]
    (println "sqlite: " version "(bundled, loaded through the FFM API); 1+...+10 =" sum)
    (when (not= 55 sum)
      (println (str "FAILED: SQLite loaded, but 1+...+10 came out as " sum ", not 55."))
      (System/exit 1))
    (println (str "OK: Java " required-java " and the bundled SQLite both work here."))
    (System/exit 0)))

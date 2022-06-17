{ config, lib, pkgs, env, ... }:

{
  imports = [ ];

  config = lib.mkIf config.collector.enable {
    collector = {
      "command" = "Start";
      "database.host" = "${config.db.host}";
      "database.port" = config.db.port;
      "database.user" = "${config.db.dataSchemaUser}";
      "database.password" = "${config.db.dataSchemaPassword}";
      "database.database" = "${config.db.database}";
      "pool.stripe" = 1;
      "pool.idletime" = 1800;
      "pool.size" = 10;
      "oddjobsstartargs.webuiauth" = "Nothing";
      "oddjobsstartargs.webuiport" = 5555;
      "oddjobsstartargs.daemonize" = "True";
      "oddjobsstartargs.pidfile" =
        "${env.collector.runDir}/my-job-collector.pid";
      "oddjobsstopargs.timeout" = 60;
      "oddjobsstopargs.pidfile" =
        "${env.collector.runDir}/my-job-collector.pid";
      "oddjobsconfig.tablename" = "${config.db.dataSchema}.jobs";
      "oddjobsconfig.jobcollector" = "";
      "oddjobsconfig.defaultmaxattempts" = 5;
      "oddjobsconfig.concurrencycontrol" = 5;
      "oddjobsconfig.dbpool" = "";
      "oddjobsconfig.pollinginterval" = 5;
      "oddjobsconfig.onjobsuccess" = "";
      "oddjobsconfig.onjobfailed" = "";
      "oddjobsconfig.onjobstart" = "";
      "oddjobsconfig.onjobtimeout" = "";
      "oddjobsconfig.pidfile" = "${env.collector.runDir}/my-job-collector.pid";
      "oddjobsconfig.logger" = "";
      "oddjobsconfig.jobtype" = "";
      "oddjobsconfig.jobtypesql" = "";
      "oddjobsconfig.defaultjobtimeout" = 1800;
      "oddjobsconfig.jobtohtml" = "";
      "oddjobsconfig.alljobtypes" = "";
      "cmdpath.xvfbpath" = "${pkgs.xvfb-run}/bin/xvfb-run";
      "cmdpath.wgetpath" = "${pkgs.wget}/bin/wget";
      "cmdpath.curlpath" = "${pkgs.curl}/bin/curl";
      "cmdpath.javapath" = "${pkgs.jdk11}/bin/java";
      "cmdpath.parsedumpshpath" = "${pkgs.eclipse-mat}/mat/ParseHeapDump.sh";
      "cmdpath.jcapath" = "${pkgs.my-jca.src}";
      # "cmdpath.gcmvpath" = "${pkgs.my-gcmv}/bin/gcmv";
      "cmdpath.gcmvpath" = "/usr/local/bin/gcmv";
      "outputpath.fetcheddumphome" = "${env.collector.dataDir}/raw_dump_files";
      "outputpath.jcapreprocessorhome" =
        "${env.collector.dataDir}/preprocessed_report_jca";
      "outputpath.matpreprocessorhome" =
        "${env.collector.dataDir}/preprocessed_report_mat";
      "outputpath.gcmvpreprocessorhome" =
        "${env.collector.dataDir}/preprocessed_report_gcmv";
      "outputpath.jcareporthome" = "${env.collector.dataDir}/parsed_report_jca";
      "outputpath.matreporthome" = "${env.collector.dataDir}/parsed_report_mat";
      "outputpath.gcmvreporthome" =
        "${env.collector.dataDir}/parsed_report_gcmv";
      "outputpath.jcapostprocessorhome" =
        "${env.collector.dataDir}/postprocessed_report_jca";
      "outputpath.matpostprocessorhome" =
        "${env.collector.dataDir}/postprocessed_report_mat";
      "outputpath.gcmvpostprocessorhome" =
        "${env.collector.dataDir}/postprocessed_report_gcmv";
      "jcacmdlineoptions.xmx" = 2048;
      "matcmdlineoptions.xmx" = 8192;
      "gcmvcmdlineoptions.xmx" = 2048;
      "gcmvcmdlineoptions.jvm" = "${pkgs.jdk11}";
      "gcmvcmdlineoptions.preference" =
        "${env.collector.dataDir}/default_preference.emf";
      "curlcmdlineoptions.loginuser" = "test1@test1.com";
      "curlcmdlineoptions.loginpin" = "pass1111";
      "curlcmdlineoptions.loginurl" = "http://${config.api-gw.serverName}:${
          toString config.api-gw.listenPort
        }/rest/rpc/login";
      "curlcmdlineoptions.uploadurl" = "http://${config.api-gw.serverName}:${
          toString config.api-gw.listenPort
        }/uploadreport";
    };
  };
}

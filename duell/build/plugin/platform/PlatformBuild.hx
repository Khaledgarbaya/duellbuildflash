/**
 * @autor kgar
 * @date 26.08.2014.
 * @company Gameduell GmbH
 */
  package duell.build.plugin.platform;
 import duell.build.objects.Configuration;
 import duell.build.objects.DuellProjectXML;
 import duell.helpers.PathHelper;
 import duell.helpers.LogHelper;
 import duell.helpers.FileHelper;
 import duell.helpers.ProcessHelper;
 import duell.helpers.TestHelper;
 import duell.objects.DuellLib;
 import duell.objects.Haxelib;
 import duell.helpers.ServerHelper;
 import duell.helpers.TemplateHelper;
 import duell.helpers.PlatformHelper;
 import duell.objects.DuellProcess;
 import duell.objects.Arguments;

 import sys.io.Process;

 import haxe.io.Path;
 class PlatformBuild
 {
 	public var requiredSetups = ["flash"];
	public var supportedHostPlatforms = [WINDOWS, MAC];
	private static inline var TEST_RESULT_FILENAME = "test_result_flash.xml";
	private static inline var DEFAULT_SERVER_URL : String = "http://localhost:3000/";
	private static inline var DELAY_BETWEEN_PYTHON_LISTENER_AND_RUNNING_THE_APP = 1;

 	private var isDebug : Bool = false;
 	private var isTest : Bool = false;
 	private var isAdvancedTelemetry : Bool = false;
	private var runInSlimerJS : Bool = false;
	private var runInBrowser : Bool = false;
	private var serverProcess : DuellProcess; 
	private var slimerProcess : DuellProcess; 
	private var fullTestResultPath : String;
 	private var targetDirectory : String;
 	private var duellBuildFlashPath : String;
 	private var projectDirectory : String;
 	private var applicationWillRunAfterBuild : Bool = false;

 	public function new()
 	{
 		checkArguments();
 	}
	public function checkArguments():Void
 	{
		if (Arguments.isSet("-debug"))
		{
			isDebug = true;
		}

		if (!Arguments.isSet("-norun"))
		{
			applicationWillRunAfterBuild = true;
		}	

		if (Arguments.isSet("-advanced-telemetry"))
		{
			isAdvancedTelemetry = true;
		}

		if (Arguments.isSet("-slimerjs"))
		{
			runInSlimerJS = true;
		}	

		if (Arguments.isSet("-browser"))
		{
			runInBrowser = true;
		}	
		
		if (Arguments.isSet("-test"))
		{
			isTest = true;
			applicationWillRunAfterBuild = true;
			Configuration.addParsingDefine("test");
		}

		if (isDebug)
		{
			Configuration.addParsingDefine("debug");
		}
		else
		{
			Configuration.addParsingDefine("release");
		}

		if(isAdvancedTelemetry)
		{
			Configuration.addParsingDefine("-advanced-telemetry");
		}
		else
		{
			Configuration.addParsingDefine("final");
		}
		/// if nothing passed slimerjs is the default
 		if(runInBrowser == false && runInSlimerJS == false)
 			runInSlimerJS = true;
 	}

 	public function parse() : Void
 	{
 	    parseProject();
 	}
 	public function parseProject() : Void
 	{
 	    var projectXML = DuellProjectXML.getConfig();
		projectXML.parse();
 	}
 	public function prepareBuild() : Void
 	{	
 		prepareVariables();

		convertDuellAndHaxelibsIntoHaxeCompilationFlags();
 	    convertParsingDefinesToCompilationDefines();
 	    prepareFlashBuild();
 	    copyJSIncludesToLibFolder();
 	    if(applicationWillRunAfterBuild)
 	    {
 	    	prepareAndRunHTTPServer();
 	    }
 	}

 	private function prepareVariables()
 	{
 	    targetDirectory = Configuration.getData().OUTPUT;
 	    projectDirectory = Path.join([targetDirectory, "flash"]);
		fullTestResultPath = Path.join([Configuration.getData().OUTPUT, "test", TEST_RESULT_FILENAME]);
 	    duellBuildFlashPath = DuellLib.getDuellLib("duellbuildflash").getPath();
 	}

 	private function convertDuellAndHaxelibsIntoHaxeCompilationFlags()
	{
		for (haxelib in Configuration.getData().DEPENDENCIES.HAXELIBS)
		{
			Configuration.getData().HAXE_COMPILE_ARGS.push("-lib " + haxelib.name + (haxelib.version != "" ? ":" + haxelib.version : ""));
		}

		for (duelllib in Configuration.getData().DEPENDENCIES.DUELLLIBS)
		{
			Configuration.getData().HAXE_COMPILE_ARGS.push("-cp " + DuellLib.getDuellLib(duelllib.name, duelllib.version).getPath());
		}

		for (path in Configuration.getData().SOURCES)
		{
			Configuration.getData().HAXE_COMPILE_ARGS.push("-cp " + path);
		}
	}
 	public function build() : Void
 	{
		var buildPath : String  = Path.join([targetDirectory,"flash","hxml"]);

		var buildProcess = new DuellProcess(
											buildPath, 
											"haxe", 
											["Build.hxml"], 
											{
												logOnlyIfVerbose : false, 
												systemCommand : true
											});
		buildProcess.blockUntilFinished();

		if (buildProcess.exitCode() != 0)
		{
			if (applicationWillRunAfterBuild)
			{
				serverProcess.kill();
			}

			LogHelper.error("Haxe Compilation Failed");
		}
 	}

 	public function run() : Void
 	{
 	    runApp();/// run app in the browser
 	}

	public function test()
	{
		testApp();
	}

	public function publish()
	{
		throw "Publishing is not yet implemented for this platform";
	}

	public function fast()
	{
		parseProject();

		prepareVariables();
 	    prepareAndRunHTTPServer();
		build();

		if (Arguments.isSet("-test"))
			testApp()
		else
			runApp();
	}

 	public function runApp() : Void
 	{
 		/// order here matters cause opening slimerjs is a blocker process	
 		if(runInBrowser)
 		{
 			ProcessHelper.openURL(DEFAULT_SERVER_URL);
 		}

 		if(runInSlimerJS)
 		{
			Sys.putEnv("SLIMERJSLAUNCHER", Path.join([duellBuildFlashPath,"bin","slimerjs-0.9.1","xulrunner","xulrunner"]));
			slimerProcess = new DuellProcess(
												Path.join([duellBuildFlashPath, "bin", "slimerjs-0.9.1"]), 
												"python", 
												["slimerjs.py","../test.js"], 
												{
													logOnlyIfVerbose : false, 
													systemCommand : true
												});
			slimerProcess.blockUntilFinished();
			serverProcess.kill();
 		} 
 		else if(runInBrowser)
 		{
			serverProcess.blockUntilFinished();
 		}
 	}
 	public function prepareAndRunHTTPServer() : Void
 	{
        var serverTargetDirectory : String  = Path.join([targetDirectory,"flash","web"]);
 		serverProcess = ServerHelper.runServer(serverTargetDirectory, duellBuildFlashPath);
 	}
 	public function prepareFlashBuild() : Void
 	{
 	    createDirectoryAndCopyTemplate();
 	}
 	public function createDirectoryAndCopyTemplate() : Void
 	{
 		/// Create directories
 		PathHelper.mkdir(targetDirectory);

 	    ///copying template files 
 	    /// index.html, expressInstall.swf and swiftObject.js
 	    TemplateHelper.recursiveCopyTemplatedFiles(Path.join([duellBuildFlashPath,"template", "flash"]), projectDirectory, Configuration.getData(), Configuration.getData().TEMPLATE_FUNCTIONS);
 	}
	private function convertParsingDefinesToCompilationDefines()
	{	

		for (define in DuellProjectXML.getConfig().parsingConditions)
		{
			if (define == "debug" )
			{
				/// not allowed
				Configuration.getData().HAXE_COMPILE_ARGS.push("-debug");
				continue;
			} 

			if (define == "flash")
			{
				/// not allowed
				continue;
			}

			Configuration.getData().HAXE_COMPILE_ARGS.push("-D " + define);
		}
	} 	

	private function copyJSIncludesToLibFolder() : Void
	{
		var jsIncludesPaths : Array<String> = [];
		var copyDestinationPath : String = "";
	    
	    for ( scriptItem in PlatformConfiguration.getData().JS_INCLUDES )
	    {
	    	copyDestinationPath = Path.join([projectDirectory,"web",scriptItem.destination]);

	    	PathHelper.mkdir(Path.directory(copyDestinationPath));
	    	if(scriptItem.applyTemplate == true)
	    	{
	    		TemplateHelper.copyTemplateFile(scriptItem.originalPath, copyDestinationPath, Configuration.getData(), Configuration.getData().TEMPLATE_FUNCTIONS);
	    	}
	    	else
	    	{
	    		FileHelper.copyIfNewer(scriptItem.originalPath, copyDestinationPath);
	    	}

	    }
	}	

	private function testApp()
	{
		/// DELETE PREVIOUS TEST
		if (sys.FileSystem.exists(fullTestResultPath))
		{
			sys.FileSystem.deleteFile(fullTestResultPath);
		}

		/// CREATE TARGET FOLDER
		PathHelper.mkdir(Path.directory(fullTestResultPath));

		/// RUN THE APP IN A THREAD
		var targetTime = haxe.Timer.stamp() + DELAY_BETWEEN_PYTHON_LISTENER_AND_RUNNING_THE_APP;
		neko.vm.Thread.create(function()
		{
			Sys.sleep(DELAY_BETWEEN_PYTHON_LISTENER_AND_RUNNING_THE_APP);

			runApp();
		});

		/// RUN THE LISTENER
		try
		{
			TestHelper.runListenerServer(60, 8181, fullTestResultPath);
		}
		catch (e:Dynamic)
		{
			serverProcess.kill();
			if (runInSlimerJS)
			{
				slimerProcess.kill();
			}
			neko.Lib.rethrow(e);
		}
		serverProcess.kill();
		if (runInSlimerJS)
		{
			slimerProcess.kill();
		}
	}

 }
import java.io.*;
import java.lang.reflect.*;
import java.util.*;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

/*
 * Headless test runner for KI5 General Fixes.
 *
 * Boots the exact Kahlua VM that Project Zomboid ships, installs a stubbed game API,
 * loads the real mod source, and runs Lua specs against it. Every test gets a fresh
 * environment, so a mod's file-level locals cannot leak between tests.
 *
 * Usage: TestRunner <gameDir> <modRoot> <luaFile> [luaFile ...]
 *   Files load in the given order. Must run with the game directory as the working
 *   directory, because Kahlua resolves stdlib.lua relative to it.
 */
public class TestRunner {

	private static String gameDir;
	private static String modRoot;
	private static String referenceRoot;
	private static final List<String> loadFiles = new ArrayList<String>();
	private static List<String> characterTraits = new ArrayList<String>();
	private static List<String> proceduralNames = new ArrayList<String>();
	private static final Map<String, Object> sandboxDefaults = new LinkedHashMap<String, Object>();
	private static int translationFailures = 0;

	public static void main(String[] args) throws Exception {
		if (args.length < 3) {
			System.out.println("usage: TestRunner <gameDir> <modRoot> <luaFile> [luaFile ...]");
			System.exit(2);
		}
		gameDir = args[0];
		modRoot = new File(args[1]).getCanonicalPath();
		for (int i = 2; i < args.length; i++) loadFiles.add(args[i]);

		// The unpacked mods this one patches, if they are on this machine. They are other
		// people's work and are not in the repository, so every check that leans on them
		// stands down rather than failing when the folder is not there.
		String reference = System.getenv("KI5GF_REFERENCE");
		referenceRoot = (reference != null && reference.trim().length() > 0)
			? new File(reference.trim()).getCanonicalPath() : null;

		characterTraits = readConstants("zombie.scripting.objects.CharacterTrait");
		System.out.println("CharacterTrait constants found in this build: " + characterTraits.size());

		proceduralNames = readProceduralNames();
		System.out.println("Loot tables found in this build: " + proceduralNames.size());

		int staticFailures = checkConstantUsage("CharacterTrait.", characterTraits)
			+ checkSandboxOptions()
			+ checkTexturePaths()
			+ checkTextureFolders()
			+ checkItemTypes()
			+ checkVehicleParts()
			+ checkExposedReturns();

		// Discovery pass: load everything once just to learn the test names.
		List<String> names;
		try {
			names = discoverTests();
		} catch (Exception e) {
			System.out.println("FATAL  could not load test environment");
			System.out.println("       " + rootCause(e));
			System.exit(1);
			return;
		}

		System.out.println("Running " + names.size() + " test(s)");
		System.out.println();

		int failures = 0;
		for (int i = 0; i < names.size(); i++) {
			Result r = runSingle(i + 1);
			if (r.ok) {
				System.out.println("  PASS  " + r.name);
			} else {
				failures++;
				System.out.println("  FAIL  " + r.name);
				for (String line : r.error.split("\n")) System.out.println("        " + line);
			}
		}

		System.out.println();
		int total = failures + staticFailures + translationFailures;
		System.out.println(total == 0
			? "ALL " + names.size() + " TEST(S) PASSED"
			: total + " FAILURE(S)");
		System.exit(total == 0 ? 0 : 1);
	}

	/* ---------- environment ---------- */

	private static KahluaTable freshEnv(J2SEPlatform platform) {
		KahluaTable env = platform.newEnvironment();

		KahluaTable traits = platform.newTable();
		for (String n : characterTraits) traits.rawset(n, n);
		env.rawset("CharacterTrait", traits);

		KahluaTable defaults = platform.newTable();
		for (Map.Entry<String, Object> e : sandboxDefaults.entrySet()) {
			defaults.rawset(e.getKey(), e.getValue());
		}
		env.rawset("KI5GF_SANDBOX_DEFAULTS", defaults);

		// Mods standing beside this one for this run, from the KI5GF_MODS environment
		// variable. Some guards run at file scope and decide whether a fix installs
		// itself at all, so the only way to exercise them is to load the whole mod again
		// with a different mod list. See the second pass in run-tests.ps1.
		KahluaTable extraMods = platform.newTable();
		String mods = System.getenv("KI5GF_MODS");
		if (mods != null && mods.trim().length() > 0) {
			String[] ids = mods.split(",");
			int n = 0;
			for (String id : ids) {
				if (id.trim().length() == 0) continue;
				extraMods.rawset(Double.valueOf(++n), id.trim());
			}
		}
		env.rawset("KI5GF_EXTRA_MODS", extraMods);

		// Every item icon the mod ships, by the name an Icon= value would use. An Icon
		// naming a texture that does not exist draws nothing and reports nothing.
		KahluaTable textures = platform.newTable();
		File[] iconDirs = {
			new File(modRoot, "common/media/textures"),
			new File(modRoot, "42/media/textures")
		};
		for (File dir : iconDirs) {
			File[] files = dir.listFiles();
			if (files == null) continue;
			for (File f : files) {
				String n = f.getName();
				if (!n.startsWith("Item_") || !n.endsWith(".png")) continue;
				textures.rawset(n.substring(5, n.length() - 4), Boolean.TRUE);
			}
		}
		env.rawset("KI5GF_ITEM_ICONS", textures);

		// Every loot table vanilla defines, so the stub builds its own from the real
		// names. A distribution naming a table that does not exist writes into nothing,
		// and the game skips it without a word, so the only way to catch a typo is for
		// the harness to know which names are real.
		KahluaTable procedural = platform.newTable();
		for (int i = 0; i < proceduralNames.size(); i++) {
			procedural.rawset(Double.valueOf(i + 1), proceduralNames.get(i));
		}
		env.rawset("KI5GF_PROCEDURAL_NAMES", procedural);

		env.rawset("KI5GF_GAME_DIR", gameDir);

		// Every script this mod ships, by file name. A few things live in a script rather
		// than in lua, and the only honest assertion about those is against what was
		// actually written. Kahlua has no io library to read them itself.
		KahluaTable scripts = platform.newTable();
		for (File dir : new File[] { new File(modRoot, "42/media/scripts"),
				new File(modRoot, "common/media/scripts") }) {
			collectScripts(dir, scripts);
		}
		env.rawset("KI5GF_MOD_SCRIPTS", scripts);
		return env;
	}

	/** Every .txt under a scripts tree, keyed by file name, recursing into subfolders. */
	private static void collectScripts(File dir, KahluaTable into) {
		File[] files = dir.listFiles();
		if (files == null) return;
		for (File f : files) {
			if (f.isDirectory()) { collectScripts(f, into); continue; }
			if (!f.getName().endsWith(".txt")) continue;
			try {
				into.rawset(f.getName(), readAll(f));
			} catch (IOException e) {
				// A script that cannot be read fails the checks above on its own.
			}
		}
	}

	private static KahluaThread load(J2SEPlatform platform, KahluaTable env) throws Exception {
		KahluaThread thread = new KahluaThread(System.out, platform, env);
		// PZ's Kahlua fork dereferences this when reporting a Lua error. Left null it
		// throws an NPE that hides the actual failure.
		thread.debugOwnerThread = Thread.currentThread();
		for (String path : loadFiles) {
			File f = new File(path);
			if (isTranslation(f)) {
				loadTranslation(platform, env, f);
				continue;
			}
			InputStream in = new FileInputStream(f);
			try {
				LuaClosure closure = LuaCompiler.loadis(in, f.getName(), env);
				thread.call(closure, new Object[0]);
			} finally {
				in.close();
			}
		}
		return thread;
	}

	private static boolean isTranslation(File f) {
		return f.getName().endsWith(".json") && f.getPath().replace('\\', '/').contains("/Translate/");
	}

	/**
	 * Build 42 translations are flat json, not lua. Keys such as "IGUI_DAMN_open_sunroof"
	 * are perfectly legal there and would be a syntax error if compiled. Every file merges
	 * into one global Translations table, so a spec can look up any key without caring
	 * which file it came from.
	 */
	private static void loadTranslation(J2SEPlatform platform, KahluaTable env, File f) throws IOException {
		Object existing = env.rawget("Translations");
		KahluaTable table = (existing instanceof KahluaTable) ? (KahluaTable) existing : platform.newTable();
		int entries = 0;

		BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
		String line;
		try {
			java.util.regex.Pattern entry =
				java.util.regex.Pattern.compile("^\\s*\"(.+?)\"\\s*:\\s*\"(.*)\"\\s*,?\\s*$");
			while ((line = r.readLine()) != null) {
				java.util.regex.Matcher m = entry.matcher(line);
				if (m.find()) {
					// The game runs every translation through String.format, so a bare
					// percent is an invalid conversion and the whole string fails to
					// render. Vanilla writes a literal percent as %%.
					//
					// %1 and %2 are the game's own positional arguments, substituted
					// before that happens, so they are not bare percents.
					String value = m.group(2);
					if (value.replace("%%", "").replaceAll("%\\d", "").indexOf('%') >= 0) {
						System.out.println("  FAIL  unescaped % in translation \"" + m.group(1)
							+ "\"  (" + f.getName() + "), vanilla writes it as %%");
						translationFailures++;
					}
					table.rawset(m.group(1), value);
					entries++;
				}
			}
		} finally {
			r.close();
		}

		env.rawset("Translations", table);
		if (entries == 0) System.out.println("WARN   no entries parsed from " + f.getName());
	}

	private static List<String> discoverTests() throws Exception {
		J2SEPlatform platform = new J2SEPlatform();
		KahluaTable env = freshEnv(platform);
		load(platform, env);

		List<String> names = new ArrayList<String>();
		Object testsObj = env.rawget("Tests");
		if (!(testsObj instanceof KahluaTable)) return names;
		Object regObj = ((KahluaTable) testsObj).rawget("Registered");
		if (!(regObj instanceof KahluaTable)) return names;

		KahluaTable reg = (KahluaTable) regObj;
		for (int i = 1; i <= reg.len(); i++) {
			Object entry = reg.rawget(Double.valueOf(i));
			if (entry instanceof KahluaTable) {
				names.add(String.valueOf(((KahluaTable) entry).rawget("Name")));
			}
		}
		return names;
	}

	private static Result runSingle(int index) {
		Result r = new Result();
		r.name = "test #" + index;
		try {
			J2SEPlatform platform = new J2SEPlatform();
			KahluaTable env = freshEnv(platform);
			KahluaThread thread = load(platform, env);

			Object fn = env.rawget("RunSingleTest");
			if (fn == null) throw new IllegalStateException("RunSingleTest is not defined by the harness");
			thread.call(fn, new Object[] { Double.valueOf(index) });

			Object name = env.rawget("TEST_NAME");
			if (name != null) r.name = String.valueOf(name);
			r.ok = Boolean.TRUE.equals(env.rawget("TEST_OK"));
			Object err = env.rawget("TEST_ERROR");
			r.error = err == null ? "no error reported" : String.valueOf(err);
		} catch (Throwable t) {
			r.ok = false;
			r.error = rootCause(t);
		}
		return r;
	}

	/* ---------- static checks ---------- */

	/**
	 * The UPPER_SNAKE constants a class declares, read out of the installed jar. Build 42
	 * renamed whole families of these at once, and a retired one is nil at runtime rather
	 * than an error, so the mod source is checked against what this build really has.
	 */
	private static List<String> readConstants(String className) {
		List<String> names = new ArrayList<String>();
		try {
			// false = do not run static initialisers, which would need a live game
			Class<?> c = Class.forName(className, false, TestRunner.class.getClassLoader());
			for (Field f : c.getDeclaredFields()) {
				if (!Modifier.isStatic(f.getModifiers())) continue;
				if (!f.getName().matches("[A-Z][A-Z0-9_]*")) continue;
				names.add(f.getName());
			}
		} catch (Throwable t) {
			System.out.println("WARN   could not read " + className + " from the jar: " + t);
		}
		return names;
	}

	/**
	 * Scans every loaded mod file for <prefix>X references and verifies each one exists
	 * in the installed build. Catches build-41 constant names in branches the tests
	 * never execute.
	 */
	private static int checkConstantUsage(String prefix, List<String> valid) throws IOException {
		if (valid.isEmpty()) return 0;
		Set<String> known = new HashSet<String>(valid);
		int bad = 0;
		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			// Only shipped mod source. Specs deliberately reference retired constants.
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;
			BufferedReader r = new BufferedReader(new FileReader(f));
			String line;
			int n = 0;
			try {
				while ((line = r.readLine()) != null) {
					n++;
					// Comments are prose and routinely name a retired constant to explain
					// why it is gone. Only real code is checked.
					int comment = line.indexOf("--");
					if (comment >= 0) line = line.substring(0, comment);

					int at = 0;
					while ((at = line.indexOf(prefix, at)) >= 0) {
						at += prefix.length();
						int end = at;
						while (end < line.length()
							&& (Character.isLetterOrDigit(line.charAt(end)) || line.charAt(end) == '_')) end++;
						String name = line.substring(at, end);
						// Constants are UPPER_SNAKE. A member starting lower case is a
						// method on the class rather than one of its constants, which is
						// how a mod defined trait has to be looked up: CharacterTrait.get
						// takes a ResourceLocation, there being no compiled constant for
						// anything the base game does not ship.
						if (name.length() > 0 && Character.isLowerCase(name.charAt(0))) continue;
						if (name.length() > 0 && !known.contains(name)) {
							bad++;
							System.out.println("  FAIL  unknown " + prefix + name
								+ "  (" + f.getName() + ":" + n + ")");
						}
					}
				}
			} finally {
				r.close();
			}
		}
		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * Checks the sandbox option file against what the parser accepts. Neither mistake
	 * here crashes: an option with a bad type is silently dropped, and one with no
	 * translation renders as its raw key.
	 */
	private static int checkSandboxOptions() throws IOException {
		File options = new File(modRoot, "42/media/sandbox-options.txt");
		if (!options.isFile()) return 0;

		// zombie.sandbox.CustomSandboxOptions.parseOption accepts exactly these.
		Set<String> types = new HashSet<String>(
			Arrays.asList("boolean", "double", "enum", "integer", "string"));

		String body = readAll(options);
		// The parser strips /* */ before reading, so the checks here must too.
		body = body.replaceAll("(?s)/\\*.*?\\*/", "");

		int bad = 0;
		if (!body.matches("(?s).*\\bVERSION\\s*=\\s*\\d+.*")) {
			bad++;
			System.out.println("  FAIL  sandbox-options.txt has no VERSION, the parser throws on load");
		}

		Set<String> keys = readTranslationKeys(
			new File(modRoot, "42/media/lua/shared/Translate/EN/Sandbox.json"));

		java.util.regex.Matcher m = java.util.regex.Pattern
			.compile("option\\s+([A-Za-z_][\\w.]*)\\s*\\{(.*?)\\}", java.util.regex.Pattern.DOTALL)
			.matcher(body);

		int found = 0;
		while (m.find()) {
			found++;
			String id = m.group(1);
			String block = m.group(2).replaceAll("\\s", "");

			String type = valueOf(block, "type");
			if (type == null || !types.contains(type)) {
				bad++;
				System.out.println("  FAIL  option " + id + " has type '" + type
					+ "', the parser only accepts " + types);
			}

			String page = valueOf(block, "page");
			if (page != null && !keys.isEmpty() && !keys.contains("Sandbox_" + page)) {
				bad++;
				System.out.println("  FAIL  option " + id + " is on page '" + page
					+ "' but Sandbox.json has no Sandbox_" + page);
			}

			// Hand the declared defaults to the specs, so the stub never has to restate
			// numbers that live in the option file.
			String def = valueOf(block, "default");
			String shortId = id.contains(".") ? id.substring(id.indexOf('.') + 1) : id;
			if (def != null) {
				// An enum reaches lua as its index, not its text: vanilla's own scenarios
				// assign SandboxVars.Alarm = 4. Seeding it as a string here would let a
				// spec pass on a comparison that errors in the game.
				if ("boolean".equals(type)) sandboxDefaults.put(shortId, Boolean.valueOf(def));
				else if ("string".equals(type)) sandboxDefaults.put(shortId, def);
				else sandboxDefaults.put(shortId, Double.valueOf(def));
			}

			String translation = valueOf(block, "translation");
			if (translation == null) {
				bad++;
				System.out.println("  FAIL  option " + id + " declares no translation");
			} else if (!keys.isEmpty() && !keys.contains("Sandbox_" + translation)) {
				bad++;
				System.out.println("  FAIL  option " + id + " has no Sandbox_" + translation
					+ " in Sandbox.json, it would render as the raw key");
			}
		}

		if (found == 0) {
			bad++;
			System.out.println("  FAIL  sandbox-options.txt parsed to zero options");
		}
		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * Resolves every getTexture path in shipped mod source against the files that
	 * actually exist, in the mod first and then the game install. A wrong path is not an
	 * error at runtime: getTexture returns null and the image simply never draws.
	 *
	 * Mod textures live under common/media or 42/media, and the game resolves a path
	 * like "media/textures/GUI/x.png" against both.
	 */
	private static int checkTexturePaths() throws IOException {
		java.util.regex.Pattern call = java.util.regex.Pattern
			.compile("getTexture\\s*\\(\\s*\"([^\"]+)\"");
		int bad = 0;

		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;

			BufferedReader r = new BufferedReader(new FileReader(f));
			String line;
			int n = 0;
			try {
				while ((line = r.readLine()) != null) {
					n++;
					int comment = line.indexOf("--");
					if (comment >= 0) line = line.substring(0, comment);

					java.util.regex.Matcher m = call.matcher(line);
					while (m.find()) {
						String texture = m.group(1);
						if (resolveTexture(texture)) continue;
						bad++;
						System.out.println("  FAIL  texture not found: " + texture
							+ "  (" + f.getName() + ":" + n + ")");
					}
				}
			} finally {
				r.close();
			}
		}

		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * The same idea for a path built at runtime, e.g. string.format("media/textures/x/%s.png", n).
	 * The file name is unknown here, so only the folder is resolved, which still catches
	 * a whole folder that was renamed or never shipped.
	 */
	private static int checkTextureFolders() throws IOException {
		java.util.regex.Pattern call = java.util.regex.Pattern
			.compile("string\\.format\\s*\\(\\s*\"(media/[^\"]*?)%");
		int bad = 0;

		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;

			BufferedReader r = new BufferedReader(new FileReader(f));
			String line;
			int n = 0;
			try {
				while ((line = r.readLine()) != null) {
					n++;
					int comment = line.indexOf("--");
					if (comment >= 0) line = line.substring(0, comment);

					java.util.regex.Matcher m = call.matcher(line);
					while (m.find()) {
						String prefix = m.group(1);
						int slash = prefix.lastIndexOf('/');
						if (slash < 0) continue;

						String dir = prefix.substring(0, slash);
						if (resolveTextureFolder(dir)) continue;
						bad++;
						System.out.println("  FAIL  texture folder empty or missing: " + dir
							+ "  (" + f.getName() + ":" + n + ")");
					}
				}
			} finally {
				r.close();
			}
		}

		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * Resolves every "Module.Name" literal in shipped mod source against the items and
	 * vehicle scripts this build actually defines, in the mod first, then the reference
	 * mods, then the game.
	 *
	 * A retired name is silent at runtime. ScriptManager.getItem returns null, a lookup
	 * keyed on the type simply never matches, and the fix does nothing with no error
	 * anywhere. Vehicle scripts get renamed between KI5 releases often enough that this
	 * is worth checking on every run rather than by eye once.
	 */
	private static int checkItemTypes() throws IOException {
		Set<String> known = readDeclarations(new File(modRoot, "42/media/scripts"), "item");
		known.addAll(readDeclarations(new File(gameDir, "media/scripts"), "item"));
		System.out.println("Item types found in this build: " + known.size());

		if (known.isEmpty()) {
			System.out.println("  FAIL  no item scripts found, nothing could be checked");
			return 1;
		}

		// Vehicle scripts share the Base module with items, so both sets have to be in
		// hand before a "Base.X" literal can be judged. The reference mods are where
		// every KI5 vehicle name lives, and they are not in the repository.
		Set<String> vehicles = readDeclarations(new File(modRoot, "42/media/scripts"), "vehicle");
		vehicles.addAll(readDeclarations(new File(gameDir, "media/scripts"), "vehicle"));
		if (referenceRoot != null) {
			vehicles.addAll(readDeclarations(new File(referenceRoot), "vehicle"));
		}
		System.out.println("Vehicle scripts found: " + vehicles.size()
			+ (referenceRoot == null ? " (reference mods not present)" : ""));
		known.addAll(vehicles);

		java.util.regex.Pattern literal = java.util.regex.Pattern
			.compile("\"([A-Za-z][A-Za-z0-9_]*)\\.([A-Za-z0-9_]+)\"");
		int bad = 0;

		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;

			BufferedReader r = new BufferedReader(new FileReader(f));
			String line;
			int n = 0;
			try {
				while ((line = r.readLine()) != null) {
					n++;
					int comment = line.indexOf("--");
					if (comment >= 0) line = line.substring(0, comment);

					java.util.regex.Matcher m = literal.matcher(line);
					while (m.find()) {
						String name = m.group(2);
						// Only literals whose bare name is a script somewhere are meant as
						// a type. Anything else is a texture path or a lua field and is
						// none of this check's business.
						if (known.contains(name)) continue;
						if (!looksLikeScriptType(m.group(1))) continue;

						bad++;
						System.out.println("  FAIL  no such item or vehicle in this build: "
							+ m.group(1) + "." + name + "  (" + f.getName() + ":" + n + ")");
					}
				}
			} finally {
				r.close();
			}
		}

		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * Resolves every getPartById("X") in shipped mod source against the parts the vehicle
	 * scripts on this machine declare. A part id that no longer exists comes back nil,
	 * and a fix guarded on it quietly stops doing anything.
	 *
	 * KI5's part ids live in KI5's own scripts, so without the reference mods there is
	 * nothing to check against and every id would read as missing. The check stands down
	 * rather than reporting a machine's setup as a failure.
	 */
	private static int checkVehicleParts() throws IOException {
		if (referenceRoot == null) return 0;

		Set<String> parts = readDeclarations(new File(referenceRoot), "part");
		parts.addAll(readDeclarations(new File(gameDir, "media/scripts"), "part"));
		parts.addAll(readDeclarations(new File(modRoot, "42/media/scripts"), "part"));
		System.out.println("Vehicle parts found across the reference mods: " + parts.size());
		if (parts.isEmpty()) return 0;

		java.util.regex.Pattern call = java.util.regex.Pattern
			.compile("getPartById\\s*\\(\\s*\"([^\"]+)\"");
		int bad = 0;

		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;

			BufferedReader r = new BufferedReader(new FileReader(f));
			String line;
			int n = 0;
			try {
				while ((line = r.readLine()) != null) {
					n++;
					int comment = line.indexOf("--");
					if (comment >= 0) line = line.substring(0, comment);

					java.util.regex.Matcher m = call.matcher(line);
					while (m.find()) {
						if (declaresPart(parts, m.group(1))) continue;
						bad++;
						System.out.println("  FAIL  no vehicle declares part " + m.group(1)
							+ "  (" + f.getName() + ":" + n + ")");
					}
				}
			} finally {
				r.close();
			}
		}

		if (bad > 0) System.out.println();
		return bad;
	}

	/**
	 * Whether any script declares this part id. A script may name a family rather than a
	 * part, as "part Door*" does, in which case the ids the game builds from it are never
	 * written down anywhere. A wildcard therefore matches by prefix, or every real id
	 * under one would read as missing.
	 */
	private static boolean declaresPart(Set<String> declared, String id) {
		if (declared.contains(id)) return true;
		for (String name : declared) {
			if (!name.endsWith("*")) continue;
			if (id.startsWith(name.substring(0, name.length() - 1))) return true;
		}
		return false;
	}

	/**
	 * Modules that name a script. Restricted so a stray "Events.OnTick" style literal is
	 * not reported as missing, while a typo inside a real module still is.
	 */
	private static boolean looksLikeScriptType(String module) {
		return module.equals("Base") || module.equals("KI5GF");
	}

	/** Every "<keyword> Name" declared under a scripts directory, bare names, no module. */
	private static Set<String> readDeclarations(File scripts, String keyword) throws IOException {
		Set<String> names = new HashSet<String>();
		if (!scripts.isDirectory()) return names;

		// A trailing star is part of the name as written: "part Door*" declares a family
		// rather than a part, and the callers here decide what to do with that.
		java.util.regex.Pattern decl = java.util.regex.Pattern
			.compile("^\\s*" + keyword + "\\s+([A-Za-z0-9_.]+\\*?)\\s*$");

		java.util.ArrayDeque<File> queue = new java.util.ArrayDeque<File>();
		queue.add(scripts);

		while (!queue.isEmpty()) {
			File dir = queue.poll();
			File[] children = dir.listFiles();
			if (children == null) continue;

			for (File f : children) {
				if (f.isDirectory()) { queue.add(f); continue; }
				if (!f.getName().endsWith(".txt")) continue;

				BufferedReader r = new BufferedReader(new FileReader(f));
				String line;
				try {
					while ((line = r.readLine()) != null) {
						java.util.regex.Matcher m = decl.matcher(line);
						if (m.matches()) names.add(m.group(1));
					}
				} finally {
					r.close();
				}
			}
		}
		return names;
	}

	/**
	 * Catches a local assigned from a call that hands back a java object lua cannot touch,
	 * and then used as one. This is exactly the shape of the crash a vehicle mod hits
	 * first: getParts() returns zombie.vehicles.VehicleParts, which is not exposed, so
	 * indexing it throws "attempted index: size of non-table" from deep inside Kahlua
	 * with no clue as to which line asked for it.
	 */
	private static int checkExposedReturns() throws IOException {
		Set<String> exposed = readExposedClasses();
		if (exposed.isEmpty()) {
			System.out.println("  FAIL  could not read LuaManager's exposed class list");
			return 1;
		}
		System.out.println("Classes exposed to lua in this build: " + exposed.size());

		// Method name to the zombie types it can return, across every exposed class.
		Map<String, Set<String>> returns = new LinkedHashMap<String, Set<String>>();
		for (String name : exposed) {
			Class<?> owner;
			try {
				owner = Class.forName(name, false, TestRunner.class.getClassLoader());
			} catch (Throwable t) {
				continue;
			}
			Method[] methods;
			try {
				methods = owner.getMethods();
			} catch (Throwable t) {
				continue;
			}
			for (Method m : methods) {
				Class<?> ret = m.getReturnType();
				if (ret.isPrimitive() || !ret.getName().startsWith("zombie.")) continue;

				Set<String> types = returns.get(m.getName());
				if (types == null) {
					types = new LinkedHashSet<String>();
					returns.put(m.getName(), types);
				}
				types.add(ret.getName());
			}
		}

		java.util.regex.Pattern assign = java.util.regex.Pattern
			.compile("local\\s+(\\w+)\\s*=\\s*\\w+[:.](\\w+)\\s*\\(");
		int bad = 0;

		for (String path : loadFiles) {
			File f = new File(path);
			if (!f.getName().endsWith(".lua")) continue;
			if (!f.getCanonicalPath().startsWith(modRoot)) continue;

			String[] lines = readAll(f).split("\\n");
			for (int n = 0; n < lines.length; n++) {
				String line = lines[n];
				int comment = line.indexOf("--");
				if (comment >= 0) line = line.substring(0, comment);

				java.util.regex.Matcher m = assign.matcher(line);
				while (m.find()) {
					String local = m.group(1);
					Set<String> types = returns.get(m.group(2));
					if (types == null || types.isEmpty()) continue;

					// Only when every type it can return is one lua cannot touch.
					boolean anyExposed = false;
					for (String t : types) if (exposed.contains(t)) anyExposed = true;
					if (anyExposed) continue;

					if (!usesLocal(lines, n + 1, local)) continue;

					bad++;
					System.out.println("  FAIL  " + m.group(2) + "() returns "
						+ types.iterator().next() + ", which lua cannot call into"
						+ "  (" + f.getName() + ":" + (n + 1) + ")");
				}
			}
		}

		if (bad > 0) System.out.println();
		return bad;
	}

	/** Whether a local is called as an object after the line it was assigned on. */
	private static boolean usesLocal(String[] lines, int from, String local) {
		java.util.regex.Pattern use = java.util.regex.Pattern
			.compile("\\b" + java.util.regex.Pattern.quote(local) + "\\s*[:]");

		for (int i = from; i < lines.length; i++) {
			if (use.matcher(lines[i]).find()) return true;
		}
		return false;
	}

	/** Class names appearing in LuaManager$Exposer, which is what lua may call into. */
	private static Set<String> readExposedClasses() throws IOException {
		Set<String> found = new LinkedHashSet<String>();
		File jar = new File(gameDir, "projectzomboid.jar");
		if (!jar.isFile()) return found;

		java.util.zip.ZipFile zip = new java.util.zip.ZipFile(jar);
		try {
			java.util.zip.ZipEntry entry = zip.getEntry("zombie/Lua/LuaManager$Exposer.class");
			if (entry == null) return found;

			ByteArrayOutputStream out = new ByteArrayOutputStream();
			InputStream in = zip.getInputStream(entry);
			byte[] buffer = new byte[8192];
			int read;
			while ((read = in.read(buffer)) > 0) out.write(buffer, 0, read);
			in.close();

			java.util.regex.Matcher m = java.util.regex.Pattern
				.compile("zombie/[A-Za-z0-9_/$]+")
				.matcher(new String(out.toByteArray(), "ISO-8859-1"));
			while (m.find()) found.add(m.group().replace('/', '.'));
		} finally {
			zip.close();
		}

		return found;
	}

	private static Set<String> readTranslationKeys(File f) throws IOException {
		Set<String> keys = new HashSet<String>();
		if (!f.isFile()) return keys;
		java.util.regex.Matcher m = java.util.regex.Pattern
			.compile("\"(.+?)\"\\s*:").matcher(readAll(f));
		while (m.find()) keys.add(m.group(1));
		return keys;
	}

	/** The name of every table in vanilla's ProceduralDistributions, in file order. */
	private static List<String> readProceduralNames() throws IOException {
		List<String> found = new ArrayList<String>();
		File file = new File(gameDir, "media/lua/server/Items/ProceduralDistributions.lua");
		if (!file.isFile()) return found;

		java.util.regex.Matcher m = java.util.regex.Pattern
			.compile("^\\t(\\w+)\\s*=\\s*\\{", java.util.regex.Pattern.MULTILINE)
			.matcher(readAll(file));
		while (m.find()) found.add(m.group(1));

		return found;
	}

	private static boolean resolveTextureFolder(String folder) {
		String relative = folder.startsWith("media/") ? folder.substring("media/".length()) : folder;

		File[] roots = {
			new File(modRoot, "common/media"),
			new File(modRoot, "42/media"),
			new File(gameDir, "media")
		};
		for (File root : roots) {
			File dir = new File(root, relative);
			String[] held = dir.list();
			if (dir.isDirectory() && held != null && held.length > 0) return true;
		}
		return false;
	}

	private static boolean resolveTexture(String texture) {
		String relative = texture.startsWith("media/") ? texture.substring("media/".length()) : texture;

		File[] roots = {
			new File(modRoot, "common/media"),
			new File(modRoot, "42/media"),
			new File(gameDir, "media")
		};
		for (File root : roots) {
			if (new File(root, relative).isFile()) return true;
		}
		return false;
	}

	private static String valueOf(String block, String key) {
		java.util.regex.Matcher m = java.util.regex.Pattern
			.compile("(?:^|,)" + key + "=([^,}]+)").matcher(block);
		return m.find() ? m.group(1) : null;
	}

	private static String readAll(File f) throws IOException {
		StringBuilder sb = new StringBuilder();
		BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
		try {
			String line;
			while ((line = r.readLine()) != null) sb.append(line).append('\n');
		} finally {
			r.close();
		}
		return sb.toString();
	}

	private static String rootCause(Throwable t) {
		Throwable c = t;
		while (c.getCause() != null) c = c.getCause();
		return c.toString();
	}

	private static class Result {
		String name;
		boolean ok;
		String error = "";
	}
}

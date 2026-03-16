extends Node
## Code taken and modified from https://github.com/Pukkah/HTML5-File-Exchange-for-Godot
## Thanks to Pukkah from GitHub for providing the original code

signal in_focus
signal image_loaded  ## Emits a signal for returning loaded image info


func _ready() -> void:
	if OS.has_feature("web"):
		_define_js()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		in_focus.emit()


func _define_js() -> void:
	(
		JavaScriptBridge
		. eval(
			"""
	var hasUnsavedChanges = false;
	function setUnsavedChanges(value) {
		hasUnsavedChanges = value;
	}

	window.addEventListener("beforeunload", function (e) {
		if (!hasUnsavedChanges) {
			return;
		}
		var confirmationMessage = "You may have unsaved changes. Are you sure you want to leave?";

		(e || window.event).returnValue = confirmationMessage; //Gecko + IE
		return confirmationMessage;                            //Webkit, Safari, Chrome
	});
	var fileData;
	var fileType;
	var fileName;
	var canceled;
	function upload_image() {
		canceled = true;
		var input = document.createElement('INPUT');
		input.setAttribute("type", "file");
		input.setAttribute(
			"accept", ".pxo, image/png, image/jpeg, image/webp, image/bmp, image/x-tga"
		);
		input.click();
		input.addEventListener('change', event => {
			if (event.target.files.length > 0){
				canceled = false;}
			var file = event.target.files[0];
			var reader = new FileReader();
			fileType = file.type;
			fileName = file.name;
			reader.readAsArrayBuffer(file);
			reader.onloadend = function (evt) {
				if (evt.target.readyState == FileReader.DONE) {
					fileData = evt.target.result;
				}
			}
		});
	}
	function upload_shader() {
		canceled = true;
		var input = document.createElement('INPUT');
		input.setAttribute("type", "file");
		input.setAttribute("accept", ".shader");
		input.click();
		input.addEventListener('change', event => {
			if (event.target.files.length > 0){
				canceled = false;}
			var file = event.target.files[0];
			var reader = new FileReader();
			fileType = file.type;
			fileName = file.name;
			reader.readAsText(file);
			reader.onloadend = function (evt) {
				if (evt.target.readyState == FileReader.DONE) {
					fileData = evt.target.result;
				}
			}
		});
	}

	// Web API integration state
	var pixeloramaApiSaveStatus = '';
	var pixeloramaApiSaveError = '';
	var pixeloramaDraftStatus = '';
	var pixeloramaDraftData = null;
	var pixeloramaDraftError = '';
	var pixeloramaApiArgs = {};  // Temporary holder for API call arguments

	// Returns the value of a URL query parameter, or null if not found.
	function getUrlParam(name) {
		return new URLSearchParams(window.location.search).get(name);
	}

	// Posts image data (base64-encoded) to a REST API endpoint via multipart/form-data.
	// Sets pixeloramaApiSaveStatus to 'done' on success or 'error:<msg>' on failure.
	async function saveImageToApi(apiUrl, b64Data, filename, mimeType) {
		pixeloramaApiSaveStatus = 'pending';
		pixeloramaApiSaveError = '';
		try {
			var binary = atob(b64Data);
			var bytes = new Uint8Array(binary.length);
			for (var i = 0; i < binary.length; i++) {
				bytes[i] = binary.charCodeAt(i);
			}
			var blob = new Blob([bytes.buffer], {type: mimeType});
			var formData = new FormData();
			formData.append('file', blob, filename);
			var response = await fetch(apiUrl, {method: 'POST', body: formData});
			if (!response.ok) {
				pixeloramaApiSaveError = 'HTTP ' + response.status;
				pixeloramaApiSaveStatus = 'error';
			} else {
				pixeloramaApiSaveStatus = 'done';
			}
		} catch(e) {
			pixeloramaApiSaveError = e.message;
			pixeloramaApiSaveStatus = 'error';
		}
	}

	// Fetches a draft (PXO or image) from the given URL.
	// Sets pixeloramaDraftStatus to 'done' (with data in pixeloramaDraftData)
	// or 'error:<msg>' on failure.
	async function loadDraftFromApi(apiUrl) {
		pixeloramaDraftStatus = 'pending';
		pixeloramaDraftData = null;
		pixeloramaDraftError = '';
		try {
			var response = await fetch(apiUrl);
			if (!response.ok) {
				pixeloramaDraftError = 'HTTP ' + response.status;
				pixeloramaDraftStatus = 'error';
			} else {
				var buffer = await response.arrayBuffer();
				pixeloramaDraftData = new Uint8Array(buffer);
				pixeloramaDraftStatus = 'done';
			}
		} catch(e) {
			pixeloramaDraftError = e.message;
			pixeloramaDraftStatus = 'error';
		}
	}
	""",
			true
		)
	)


## If (load_directly = false) then image info (image and its name)
## will not be directly forwarded it to OpenSave
func load_image(load_directly := true) -> void:
	if !OS.has_feature("web"):
		return
	# Execute JS function
	JavaScriptBridge.eval("upload_image();", true)  # Opens prompt for choosing file
	await in_focus  # Wait until JS prompt is closed
	await get_tree().create_timer(0.5).timeout  # Give some time for async JS data load

	if JavaScriptBridge.eval("canceled;", true) == 1:  # If File Dialog closed w/o file
		return

	# Use data from png data
	var image_data: PackedByteArray
	while true:
		image_data = JavaScriptBridge.eval("fileData;", true)
		if image_data != null:
			break
		await get_tree().create_timer(1.0).timeout  # Need more time to load data

	var image_type: String = JavaScriptBridge.eval("fileType;", true)
	var image_name: String = JavaScriptBridge.eval("fileName;", true)

	var image := Image.new()
	var image_error: Error
	var image_info := {}
	match image_type:
		"image/png":
			if load_directly:
				# In this case we can afford to try APNG,
				# because we know we're sending it through OpenSave handling.
				# Otherwise we could end up passing something incompatible.
				var res := AImgIOAPNGImporter.load_from_buffer(image_data)
				if res[0] == null:
					# Success, pass to OpenSave.
					OpenSave.handle_loading_aimg(image_name, res[1])
					return
			image_error = image.load_png_from_buffer(image_data)
		"image/jpeg":
			image_error = image.load_jpg_from_buffer(image_data)
		"image/webp":
			image_error = image.load_webp_from_buffer(image_data)
		"image/bmp":
			image_error = image.load_bmp_from_buffer(image_data)
		"image/x-tga":
			image_error = image.load_tga_from_buffer(image_data)
		var invalid_type:
			if image_name.get_extension().to_lower() == "pxo":
				var temp_file_path := "user://%s" % image_name
				var temp_file := FileAccess.open(temp_file_path, FileAccess.WRITE)
				temp_file.store_buffer(image_data)
				temp_file.close()
				OpenSave.open_pxo_file(temp_file_path)
				DirAccess.remove_absolute(temp_file_path)
				return
			print("Invalid type: " + invalid_type)
			return
	if image_error:
		print("An error occurred while trying to display the image.")
		return
	else:
		image_info = {"image": image, "name": image_name}
		if load_directly:
			OpenSave.handle_loading_image(image_name, image)
	image_loaded.emit(image_info)


func load_shader() -> void:
	if !OS.has_feature("web"):
		return

	# Execute JS function
	JavaScriptBridge.eval("upload_shader();", true)  # Opens prompt for choosing file

	await in_focus  # Wait until JS prompt is closed
	await get_tree().create_timer(0.5).timeout  # Give some time for async JS data load

	if JavaScriptBridge.eval("canceled;", true):  # If File Dialog closed w/o file
		return

	# Use data from png data
	var file_data
	while true:
		file_data = JavaScriptBridge.eval("fileData;", true)
		if file_data != null:
			break
		await get_tree().create_timer(1.0).timeout  # Need more time to load data

#	var file_type = JavaScriptBridge.eval("fileType;", true)
	var file_name = JavaScriptBridge.eval("fileName;", true)

	var shader := Shader.new()
	shader.code = file_data

	var shader_effect_dialog = Global.control.get_node("Dialogs/ImageEffects/ShaderEffect")
	if is_instance_valid(shader_effect_dialog):
		shader_effect_dialog.change_shader(shader, file_name.get_basename())


## Returns the value of a URL query parameter when running on the web,
## or an empty string if not found or not on web.
## This allows the embedding website to pass configuration to Pixelorama
## via URL parameters (e.g. [code]?save_api_url=https://example.com/save[/code]).
func get_url_param(param_name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	# Use URLSearchParams directly to avoid depending on _define_js() having been called.
	# Use JSON.stringify to safely embed the param name into the JS code.
	var result = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get(%s);" % JSON.stringify(param_name), true
	)
	if result == null:
		return ""
	return str(result)


## Posts binary [param buffer] data to [param api_url] using a multipart/form-data POST request.
## The file field name in the form is [code]file[/code].
## Returns [code]true[/code] on success, [code]false[/code] on failure.
## Only works when running on the web.
func save_to_api(
	api_url: String, buffer: PackedByteArray, filename: String, mime_type: String
) -> bool:
	if not OS.has_feature("web"):
		return false
	var b64 := Marshalls.raw_to_base64(buffer)
	# Set the URL, filename, and MIME type via JSON.stringify so special characters are
	# properly escaped, preventing JS injection from user-controlled values.
	JavaScriptBridge.eval(
		(
			"pixeloramaApiArgs = {url: %s, filename: %s, mime: %s};"
			% [JSON.stringify(api_url), JSON.stringify(filename), JSON.stringify(mime_type)]
		),
		true
	)
	# base64 only contains A-Za-z0-9+/= which are safe inside a single-quoted JS string.
	JavaScriptBridge.eval(
		"saveImageToApi(pixeloramaApiArgs.url, '%s', pixeloramaApiArgs.filename, pixeloramaApiArgs.mime);"
		% b64,
		true
	)
	# Poll until the JS async operation completes
	while true:
		var status: String = str(JavaScriptBridge.eval("pixeloramaApiSaveStatus;", true))
		if status == "done":
			return true
		if status == "error":
			var err_msg: String = str(JavaScriptBridge.eval("pixeloramaApiSaveError;", true))
			push_error("API save failed: %s" % err_msg)
			return false
		await get_tree().create_timer(0.2).timeout
	return false  # Unreachable, satisfies GDScript return analysis


## Fetches a draft file (PXO or image) from [param api_url] via an HTTP GET request
## and returns the raw bytes.
## Returns an empty [PackedByteArray] on failure.
## Only works when running on the web.
func load_draft_from_api(api_url: String) -> PackedByteArray:
	if not OS.has_feature("web"):
		return PackedByteArray()
	# Use JSON.stringify to safely embed api_url into the JS call, preventing injection.
	JavaScriptBridge.eval("loadDraftFromApi(%s);" % JSON.stringify(api_url), true)
	# Poll until the JS async operation completes
	while true:
		var status: String = str(JavaScriptBridge.eval("pixeloramaDraftStatus;", true))
		if status == "done":
			var data: PackedByteArray = JavaScriptBridge.eval("pixeloramaDraftData;", true)
			return data
		if status == "error":
			var err_msg: String = str(JavaScriptBridge.eval("pixeloramaDraftError;", true))
			push_error("API draft load failed: %s" % err_msg)
			return PackedByteArray()
		await get_tree().create_timer(0.2).timeout
	return PackedByteArray()  # Unreachable, satisfies GDScript return analysis

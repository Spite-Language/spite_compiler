# mapping

The program's folders: which class file each name reaches.

- `mapping.spite`: the entry, `Mapping(folder)`; its `run` answers a `folder_map.spite`.
- `mapped_folder.spite`, `class_file.spite` and `library_file.spite`: a folder, a class file and a library file of the map.
- `standard_library.spite`: the singleton holding the library's folder and system, chosen once by `command_line`;
  it says whether a path is the library's and shows a library file by its place in the library (D2242).
  `loaded_library.spite` is what `validators/mapping/library_load` is handed about a `load`.
- `shown_paths.spite`: the singleton every root of the map is added to; it names a file in a crash site by its root's
  folder and its place inside it (a library file as `standard_library.spite` shows it), never where the build ran.
- `packages.spite` and `pinned_copy.spite`: the package a path belongs to and the copy of a git-pinned one.
- `folder_map.spite`'s `makes_a_class` is the one place that says whether a folder is a class: a root holding its own
  file is one (the program's entry class is its root, D2669, D2676), a root without one and the library are not.
  `join_the_library_reopenings` gives a root class's file or folder named like a library class or folder the
  library's name, so it reopens it.
- `names.spite`: the last segment of a path, and the one right spelling of a name.
- `misnamed.spite`: a file or folder of the program not named in snake_case that has one right spelling; the map
  notes it instead of refusing it and names its classes by the right spelling, and `fixes/symbols/misnamed_path` renames it.

What it finds wrong is handed to the rules of `validators/mapping`.

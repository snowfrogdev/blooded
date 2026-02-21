class_name ContextBehavior3D
extends Resource
## Abstract base for context steering behaviors.
##
## Behaviors populate a [ContextMap3D] with interest, danger, or both.
## Interest represents desirable directions; danger represents directions to avoid.
## Values are max-merged per slot — multiple behaviors can write to the same
## channel without overwriting each other. The orchestrator calls
## [method ContextMap3D.evaluate] after all behaviors have populated the map.
##
## Concrete subclasses that hold per-agent state (caches, physics queries, etc.)
## must set [code]resource_local_to_scene = true[/code] in [method _init].


func populate(_agent: Node3D, _kinematic: Kinematic3D, _map: ContextMap3D) -> void:
	push_error("ContextBehavior3D.populate() is abstract — subclass must override")

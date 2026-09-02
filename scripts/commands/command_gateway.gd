class_name CommandGateway
extends Node

signal command_submitted(command: GameCommand)


func submit(command: GameCommand) -> void:
	command_submitted.emit(command)

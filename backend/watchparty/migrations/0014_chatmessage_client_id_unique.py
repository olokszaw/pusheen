from django.db import migrations, models


CONSTRAINT_NAME = "unique_room_user_client_message"


def add_constraint_if_missing(apps, schema_editor):
    """Handle databases where an older build created the index out of band."""
    ChatMessage = apps.get_model("watchparty", "ChatMessage")
    table = ChatMessage._meta.db_table
    with schema_editor.connection.cursor() as cursor:
        constraints = schema_editor.connection.introspection.get_constraints(cursor, table)
    if CONSTRAINT_NAME in constraints:
        return
    schema_editor.add_constraint(
        ChatMessage,
        models.UniqueConstraint(
            condition=~models.Q(client_message_id=""),
            fields=("room", "user", "client_message_id"),
            name=CONSTRAINT_NAME,
        ),
    )


def remove_constraint_if_present(apps, schema_editor):
    ChatMessage = apps.get_model("watchparty", "ChatMessage")
    table = ChatMessage._meta.db_table
    with schema_editor.connection.cursor() as cursor:
        constraints = schema_editor.connection.introspection.get_constraints(cursor, table)
    if CONSTRAINT_NAME not in constraints:
        return
    schema_editor.remove_constraint(
        ChatMessage,
        models.UniqueConstraint(
            condition=~models.Q(client_message_id=""),
            fields=("room", "user", "client_message_id"),
            name=CONSTRAINT_NAME,
        ),
    )


class Migration(migrations.Migration):
    dependencies = [("watchparty", "0013_chatmessage_client_message_id")]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_constraint_if_missing,
                    remove_constraint_if_present,
                ),
            ],
            state_operations=[
                migrations.AddConstraint(
                    model_name="chatmessage",
                    constraint=models.UniqueConstraint(
                        condition=~models.Q(client_message_id=""),
                        fields=("room", "user", "client_message_id"),
                        name=CONSTRAINT_NAME,
                    ),
                ),
            ],
        ),
    ]

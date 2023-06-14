import logging
from datetime import datetime
import azure.functions as func
import azureml
from azureml.core import Workspace, Experiment, Datastore
from azureml.pipeline.core import PipelineData, Pipeline
from azureml.data.data_reference import DataReference
from azureml.pipeline.steps import PythonScriptStep
import pandas as pd
from azureml.core.compute import ComputeTarget, ComputeInstance
from azureml.core.compute_target import ComputeTargetException
import os


def main(myblob: func.InputStream):
    # Set up Azure ML workspace and experiment
    workspace = Workspace.get(name="mlflowtask-resourcegroup", subscription_id="42a759f3-b606-45d2-9041-96e028b0c0c0", resource_group="taskresourcegroup")    experiment = Experiment(workspace=workspace, name="taskmlflow")
    experiment = Experiment(workspace=workspace, name="taskmlflow")

    blob_output_datastore_name = "outputdatastore"
    blob_input_datastore_name = "inputdatastore"
    blob_output_datastore = Datastore.register_azure_blob_container(
           workspace=workspace,
           datastore_name=blob_output_datastore_name,
           account_name="taskinputs", # Storage account name
           container_name="inputcontainer", # Name of Azure blob container
           account_key="PXPcfLhYNjeiqXiw/Zi5TS2Vu3qwXuUjcviHWZn1iY44dUjmkfrul1bFxCOG7tx8cjqpkYGvBcOB+AStnBFRTA==") # Storage account key

    blob_input_datastore = Datastore.register_azure_blob_container(
           workspace=workspace,
           datastore_name=blob_input_datastore_name,
           account_name="taskoutputs", # Storage account name
           container_name="outputcontainer", # Name of Azure blob container
           account_key="iDVbq8VfYxAvRhRYHex83xQOwySKkZL8Vadu+cMnyqC1okx/p3M/Q8FCFAgbj1kBpgM6k5aMvVS4+AStY4eZtg==") # Storage account key
    
    output_data = PipelineData("output_data", datastore=Datastore(workspace, blob_output_datastore_name))

    input_data_1 = DataReference(datastore=Datastore(workspace, "departmentdatastore"),data_reference_name="departmentsinput1", 
                                        path_on_datastore="/departmentsinput1.csv")

    input_data_2 = DataReference(datastore=Datastore(workspace, "employeedatastore"),data_reference_name="employeesinput2", 
                                        path_on_datastore="/employeesinput2.csv")

    # Define dataset versioning based on input data modification time
    input_data_version = datetime.now().strftime("%Y%m%d%H%M%S")

    # Define MLflow environment
    mlflow_env = azureml.core.Environment.from_conda_specification(name="mlflow-env", file_path="conda.yml")

    #Define validation and combination script
    script_name = "validate_and_combine.py"
    script_params = [
        "--input1", input_data_1,
        "--input2", input_data_2,
        "--output", output_data,
    ]
    
    #Create compute instance
    compute_name = "taskmlflow-instance"
    compute_config = ComputeInstance.provisioning_configuration(
        vm_size="Standard_DS2_v2"
    )
    
    try:
        # Check if the compute instance already exists
        compute_instance = ComputeTarget(workspace, compute_name)
        print("Found existing compute instance.")
    except ComputeTargetException:
        # If the compute instance doesn't exist, create it
        compute_instance = ComputeInstance.create(workspace, compute_name, compute_config)
        compute_instance.wait_for_completion(show_output=True)
    

    # Define validation and combination step
    validation_combination_step = PythonScriptStep(
        name="Validation and Combination",
        source_directory = os.path.dirname(os.path.realpath(__file__)),
        script_name=script_name,
        arguments=script_params,
        inputs=[input_data_1, input_data_2],
        outputs=[output_data],
        compute_target="taskmlflow-instance",
        runconfig={
            "environment": mlflow_env
        }
    )

    # Create MLflow pipeline
    pipeline = Pipeline(workspace=workspace, steps=[validation_combination_step])

    # Connect the inputs and outputs between steps
    pipeline.validate()
    pipeline_run = experiment.submit(pipeline)
    pipeline_run.wait_for_completion()

    # Call combine_csv function with input and output paths

    logging.info("MLflow pipeline triggered successfully")

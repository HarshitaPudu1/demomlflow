import pandas as pd
import argparse
import os.path
import datetime

def validate_csv(file_path):
    # Load CSV file into a DataFrame
    df = pd.read_csv(file_path)
    return df

def combine_csv(input1, input2, output):
    # Perform data validation on both input files
    validated_data1 = validate_csv(input1)
    validated_data2 = validate_csv(input2)

    # Combine validated data
    combined_data = pd.concat([validated_data1, validated_data2], axis=0)

    # Save combined data as Parquet
    combined_data.to_parquet(output, index=False)

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser()
    parser.add_argument("--input1", type=str, help="Path to input CSV file 1")
    parser.add_argument("--input2", type=str, help="Path to input CSV file 2")
    parser.add_argument("--output", type=str, help="Path to output Parquet file")
    args = parser.parse_args()
    print(args.input1)

    # Call combine_csv function with input and output paths
    combine_csv(args.input1, args.input2, args.output)

if __name__ == "__main__":
    main()
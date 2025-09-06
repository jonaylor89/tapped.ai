import React, { useEffect, useState } from 'react';

const ProductNameField = ({ formData, updateFormData, onValidation }) => {
  const [error, setError] = useState<string | null>(null);
  let product = '';

  if (formData['marketing_field'] === 'single') {
    product = 'single';
  } else if (formData['marketing_field'] === 'EP') {
    product = 'EP';
  } else {
    product = 'album';
  }

  const validateForUI = (value: string) => {
    if (value.trim() === '') {
      setError('Product name cannot be empty');
      onValidation(false);
    } else {
      setError(null);
      onValidation(true);
    }
  };

  const justValidate = (value: string) => {
    if (value.trim() === '') {
      onValidation(false);
    } else {
      onValidation(true);
    }
  };

  useEffect(() => {
    justValidate(formData['productName'] || '');
  }, [formData['productName']]);

  const handleInputChange = (e: { target: { name: any; value: any; }; }) => {
    const { name, value } = e.target;
    updateFormData({
      ...formData,
      [name]: value,
    });
    validateForUI(value);
  };

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start px-6">
        <h1 className="mb-2 text-2xl font-bold text-white">
          what is the name of the {product}?
        </h1>
        <div className="flex h-full w-full items-center justify-center">
          <input
            type="text"
            name="productName"
            placeholder="type here..."
            value={formData['productName'] || ''}
            onChange={handleInputChange}
            className={`white_placeholder w-full appearance-none rounded ${
              error ? 'border-2 border-red-500' : ''
            } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white focus:text-black font-semibold focus:outline-none`}
          />
        </div>
        {error && <p className="mt-2 text-red-500">{error}</p>}

        <div className="grid w-full grid-cols-3 items-center my-4">
          <div className="h-px bg-gray-300"></div>
          <span className="text-center text-white">or</span>
          <div className="h-px bg-gray-300"></div>
        </div>

        <div className="flex flex-col w-full">
          <button
            className="mb-2 px-4 py-2 rounded-xl bg-white text-black font-semibold"
            onClick={() => {
              updateFormData({ ...formData, productName: 'untitled' });
              validateForUI('untitled');
            }}
          >
            untitled
          </button>
        </div>
      </div>
    </div>
  );
};

export default ProductNameField;

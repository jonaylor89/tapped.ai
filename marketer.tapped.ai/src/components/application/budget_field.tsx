import React, { useEffect, useState } from 'react';

const BudgetField = ({ formData, updateFormData, onValidation }) => {
  const [error, setError] = useState<string | null>(null);
  const [hasInteracted, setHasInteracted] = useState(false);
  let product = '';

  if (formData['marketingType'] === 'single') {
    product = 'single';
  } else if (formData['marketingType'] === 'EP') {
    product = 'EP';
  } else {
    product = 'album';
  }

  const handleInputChange = (e) => {
    setHasInteracted(true);

    const { value } = e.target;
    updateFormData({ ...formData, ['budget']: value });
    validateForUI(value);
  };

  const validateForUI = (value) => {
    if (hasInteracted) {
      if (!value) {
        setError('Please select your budget.');
        onValidation(false);
      } else {
        setError(null);
        onValidation(true);
      }
    } else {
      setError(null);
      onValidation(false);
    }
  };

  const justValidate = (value) => {
    if (!value) {
      onValidation(false);
    } else {
      onValidation(true);
    }
  };

  useEffect(() => {
    justValidate(formData['budget']);
  }, [formData['budget']]);

  const options = [
    '$0',
    '$100',
    '$250',
    '$500',
    '$1000',
    '$1000+',
  ];

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start px-6">
        <h1 className="mb-2 text-2xl font-bold text-white">
          what is your budget?
        </h1>

        <input
          type="text"
          name="budget"
          placeholder="type here..."
          onChange={handleInputChange}
          value={formData['budget'] || ''}
          className={`white_placeholder w-full appearance-none rounded ${
            error ? 'border-2 border-red-500' : ''
          } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white focus:text-black font-semibold focus:outline-none`}
        />

        <div className="grid w-full grid-cols-3 items-center my-4">
          <div className="h-px bg-gray-300"></div>
          <span className="text-center text-white">or</span>
          <div className="h-px bg-gray-300"></div>
        </div>

        <div className="flex flex-wrap w-full justify-between">
          {options.map((option) => (
            <div key={option} className="w-1/2 flex items-center justify-center mb-4 pr-2">
              <input
                type="radio"
                id={option}
                name="budget"
                value={option}
                checked={formData['budget'] === option}
                onChange={handleInputChange}
                className="sr-only"
              />
              <label
                htmlFor={option}
                className={`w-full text-center px-4 py-2 rounded-xl cursor-pointer transition duration-200 ease-in-out 
                ${formData['budget'] === option ? 'bg-white font-bold text-black' : 'bg-[#63b2fd] font-bold text-white'}`}
              >
                {option}
              </label>
            </div>
          ))}
        </div>

        {error && <p className="text-red-500">{error}</p>}
      </div>
    </div>
  );
};

export default BudgetField;

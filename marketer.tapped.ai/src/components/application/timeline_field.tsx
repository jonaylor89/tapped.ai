import React, { useEffect, useState } from 'react';

const TimelineField = ({ formData, updateFormData, onValidation }) => {
  const [error, setError] = useState(null);
  const [hasInteracted, setHasInteracted] = useState(false);

  const handleInputChange = (e) => {
    setHasInteracted(true);

    const { value } = e.target;
    updateFormData({ ...formData, ['timeline']: value });
    validateForUI(value);
  };

  const validateForUI = (value) => {
    if (hasInteracted) {
      if (!value) {
        setError('Please select your timeline.');
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
    justValidate(formData['timeline']);
  }, [formData['timeline']]);

  const options = [
    'released a week ago',
    'just released',
    '1 week',
    '2 weeks',
    '1 month',
    '3 months',
    '6 months',
    '1 year',
  ];

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start px-6">
        <h1 className="mb-2 text-2xl font-bold text-white">
          what is your release timeline?
        </h1>
        <div className="flex flex-wrap w-full justify-between">
          {options.map((option) => (
            <div key={option} className="w-1/2 flex items-center justify-center mb-4 pr-2">
              <input
                type="radio"
                id={option}
                name="timeline"
                value={option}
                checked={formData['timeline'] === option}
                onChange={handleInputChange}
                className="sr-only"
              />
              <label
                htmlFor={option}
                className={`w-full text-center px-4 py-2 rounded-xl cursor-pointer transition duration-200 ease-in-out 
                ${formData['timeline'] === option ? 'bg-white font-bold text-black' : 'bg-[#63b2fd] font-bold text-white'}`}
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

export default TimelineField;

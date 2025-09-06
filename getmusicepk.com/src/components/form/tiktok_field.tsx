import React, { useEffect, useState } from 'react';

const TiktokField = ({ formData, updateFormData, onValidation, user }) => {
  const [error, setError] = useState(null);

  useEffect(() => {
    if (user && user.tiktokHandle) {
      updateFormData({
        ...formData,
        tiktokHandle: user.tiktokHandle,
      });
    }
  }, [user]);  

  const validateForUI = (value) => {
    if (value.trim() === '') {
      setError('tiktok handle cannot be empty');
      onValidation(false);
    } else {
      setError(null);
      onValidation(true);
    }
  };

  useEffect(() => {
    const justValidate = (value) => {
      if (value.trim() === '') {
        onValidation(false);
      } else {
        onValidation(true);
      }
    };
    justValidate(formData['tiktokHandle'] || '');
  }, [formData, onValidation]);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    updateFormData({
      ...formData,
      [name]: value,
    });
    validateForUI(value);
  };

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start">
        <h1 className="mb-2 text-2xl font-bold text-white">
          what is your tiktok handle?
        </h1>
        <div className="flex h-full w-full items-center justify-center">
          <input
            type="text"
            name="tiktokHandle"
            placeholder="type here..."
            value={formData['tiktokHandle'] || ''}
            onChange={handleInputChange}
            className={`white_placeholder w-full appearance-none rounded ${error ? 'border-2 border-red-500' : ''
              } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white focus:text-black font-semibold focus:outline-none`}
          />
        </div>
        {error && <p className="mt-2 text-red-500">{error}</p>}
      </div>
    </div>
  );
};

export default TiktokField;
